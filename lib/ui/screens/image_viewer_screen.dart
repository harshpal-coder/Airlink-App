import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saver_gallery/saver_gallery.dart';
import '../../core/constants.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imagePath;
  final String heroTag;

  const ImageViewerScreen({
    super.key,
    required this.imagePath,
    required this.heroTag,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  Future<void> _saveToGallery() async {
    try {
      final file = File(widget.imagePath);
      if (!file.existsSync()) {
        _showSnack('Image file not found.');
        return;
      }
      final bytes = await file.readAsBytes();
      final result = await SaverGallery.saveImage(
        bytes,
        quality: 95,
        fileName: 'airlink_${DateTime.now().millisecondsSinceEpoch}',
        androidRelativePath: 'Pictures/AirLink',
        skipIfExists: false,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        _showSnack('✅ Saved to gallery!');
      } else {
        _showSnack('❌ Could not save: ${result.errorMessage}');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('❌ Error saving: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppColors.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Image', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 26),
            tooltip: 'Save to Gallery',
            onPressed: _saveToGallery,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Hero(
          tag: widget.heroTag,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              errorBuilder: (ctx, err, st) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
                  const SizedBox(height: 12),
                  Text('Could not load image', style: GoogleFonts.inter(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ElevatedButton.icon(
            onPressed: _saveToGallery,
            icon: const Icon(Icons.download_rounded),
            label: Text('Save to Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
          ),
        ),
      ),
    );
  }
}
