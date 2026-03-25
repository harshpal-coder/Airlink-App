import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../services/chat_provider.dart';
import '../../models/message_model.dart';
import '../../core/constants.dart';
import 'image_viewer_screen.dart';

class SharedMediaScreen extends StatelessWidget {
  final String peerUuid;
  final String peerName;

  const SharedMediaScreen({
    super.key,
    required this.peerUuid,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceDark,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Shared Media',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
            unselectedLabelStyle: GoogleFonts.inter(),
            tabs: const [
              Tab(text: 'MEDIA'),
              Tab(text: 'DOCS'),
            ],
          ),
        ),
        body: Consumer<ChatProvider>(
          builder: (context, provider, child) {
            return FutureBuilder<List<Message>>(
              future: provider.getSharedMedia(peerUuid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                
                final mediaList = snapshot.data ?? [];
                if (mediaList.isEmpty) {
                  return _buildEmptyState();
                }

                final images = mediaList.where((m) => m.type == MessageType.image).toList();
                final docs = mediaList.where((m) => m.type == MessageType.file).toList();

                return TabBarView(
                  children: [
                    _buildMediaGrid(context, images),
                    _buildDocsList(context, provider, docs),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.perm_media_outlined, size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No shared media found',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(BuildContext context, List<Message> images) {
    if (images.isEmpty) return _buildEmptyState();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final msg = images[index];
        final path = msg.imagePath ?? msg.content;
        
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageViewerScreen(
                  imagePath: path,
                  heroTag: 'media_${msg.id}',
                ),
              ),
            );
          },
          child: Hero(
            tag: 'media_${msg.id}',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: FileImage(File(path)),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocsList(BuildContext context, ChatProvider provider, List<Message> docs) {
    if (docs.isEmpty) return _buildEmptyState();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (context, index) => const Divider(color: Colors.white10),
      itemBuilder: (context, index) {
        final msg = docs[index];
        final fileName = msg.fileName ?? p.basename(msg.content);
        final fileSize = msg.fileSize != null ? _formatBytes(msg.fileSize!) : '';
        
        return ListTile(
          onTap: () => provider.openFile(msg.content),
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getFileIcon(fileName), color: AppColors.primaryLight),
          ),
          title: Text(
            fileName,
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '$fileSize · ${msg.timestamp.day}/${msg.timestamp.month}/${msg.timestamp.year}',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        );
      },
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if (ext == '.doc' || ext == '.docx') return Icons.description_outlined;
    if (ext == '.xls' || ext == '.xlsx') return Icons.table_chart_outlined;
    if (ext == '.zip' || ext == '.rar') return Icons.compress_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes / 1024).floor() == 0 ? 0 : (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    final value = bytes / (1 << (i * 10));
    return '${value.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
