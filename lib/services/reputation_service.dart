import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../utils/connectivity_logger.dart';

class ReputationService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  static const double minScore = 0.0;
  static const double maxScore = 100.0;
  static const double initialScore = 50.0;
  
  // Weighting factors
  static const double successWeight = 2.0;
  static const double failWeight = -5.0; // Failures are more significant
  static const double timeWeightPerMinute = 0.1;

  /// Updates a peer's reputation based on a connection event.
  Future<void> recordConnectionEvent(String uuid, bool success, {int? durationMinutes}) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'peer_reputation',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    double currentScore = initialScore;
    int successes = 0;
    int fails = 0;
    int totalTime = 0;

    if (existing.isNotEmpty) {
      currentScore = existing.first['score'] as double;
      successes = existing.first['success_count'] as int;
      fails = existing.first['fail_count'] as int;
      totalTime = existing.first['total_time_minutes'] as int;
    }

    if (success) {
      successes++;
      currentScore += successWeight;
      if (durationMinutes != null) {
        totalTime += durationMinutes;
        currentScore += (durationMinutes * timeWeightPerMinute);
      }
    } else {
      fails++;
      currentScore += failWeight;
    }

    // Clamp score
    currentScore = currentScore.clamp(minScore, maxScore);

    await db.insert(
      'peer_reputation',
      {
        'uuid': uuid,
        'score': currentScore,
        'success_count': successes,
        'fail_count': fails,
        'total_time_minutes': totalTime,
        'last_updated': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    ConnectivityLogger.debug(
      LogCategory.discovery,
      'Updated reputation for $uuid: Score $currentScore (S:$successes, F:$fails)',
    );
  }

  /// Retrieves the reputation metrics for a specific peer.
  /// Returns a composite score: (Local * 0.7) + (Consensus * 0.3)
  Future<Map<String, dynamic>?> getReputation(String uuid) async {
    final db = await _dbHelper.database;
    final res = await db.query(
      'peer_reputation',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    if (res.isEmpty) return null;

    final data = Map<String, dynamic>.from(res.first);
    double localScore = data['score'] as double;
    double consensusScore = data['consensus_score'] as double;
    
    // Composite Calculation
    data['composite_score'] = (localScore * 0.7) + (consensusScore * 0.3);
    
    return data;
  }

  /// Merges gossip data from a trusted neighbor.
  Future<void> mergeGossipData(String sourceUuid, Map<String, dynamic> gossip) async {
    final db = await _dbHelper.database;
    
    for (var entry in gossip.entries) {
      final peerUuid = entry.key;
      final double neighborScore = (entry.value as num).toDouble();

      final existing = await db.query(
        'peer_reputation',
        where: 'uuid = ?',
        whereArgs: [peerUuid],
      );

      if (existing.isEmpty) {
        // New peer known only via gossip
        await db.insert('peer_reputation', {
          'uuid': peerUuid,
          'score': initialScore, // Local experience is neutral
          'consensus_score': neighborScore,
          'consensus_count': 1,
          'last_updated': DateTime.now().toIso8601String(),
        });
      } else {
        double currentConsensus = existing.first['consensus_score'] as double;
        int count = existing.first['consensus_count'] as int;

        // Moving average for consensus
        double newConsensus = ((currentConsensus * count) + neighborScore) / (count + 1);
        
        await db.update(
          'peer_reputation',
          {
            'consensus_score': newConsensus.clamp(minScore, maxScore),
            'consensus_count': count + 1,
            'last_updated': DateTime.now().toIso8601String(),
          },
          where: 'uuid = ?',
          whereArgs: [peerUuid],
        );
      }
    }
    
    ConnectivityLogger.info(LogCategory.discovery, 'Merged reputation gossip from $sourceUuid (${gossip.length} peers)');
  }

  /// Returns the top-N reputable peers to gossip about.
  Future<Map<String, double>> getTopPeersForGossip({int limit = 10}) async {
    final db = await _dbHelper.database;
    final res = await db.query(
      'peer_reputation',
      where: 'score > ?',
      whereArgs: [60.0], // Only gossip about "Stable" or better peers
      orderBy: 'score DESC',
      limit: limit,
    );

    return { for (var row in res) row['uuid'] as String : row['score'] as double };
  }

  /// Calculates a "Stability" label based on score.
  String getStabilityLabel(double score) {
    if (score >= 80) return 'Highly Stable';
    if (score >= 60) return 'Stable';
    if (score >= 40) return 'Average';
    if (score >= 20) return 'Unstable';
    return 'Blacklisted/Very Unstable';
  }
}
