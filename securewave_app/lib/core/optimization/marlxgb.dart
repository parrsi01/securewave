import '../models/server_region.dart';

class MarLXGBPredictor {
  const MarLXGBPredictor({
    this.recentWeight = 0.65,
    this.favoriteBoost = 0.15,
  });

  final double recentWeight;
  final double favoriteBoost;

  double predictBandwidth({
    required double previous,
    required double sample,
    double min = 1,
    double max = 250,
  }) {
    if (previous <= 0) {
      return sample.clamp(min, max).toDouble();
    }
    final blended = (previous * recentWeight) + (sample * (1 - recentWeight));
    return blended.clamp(min, max).toDouble();
  }

  double scoreServer(ServerRegion region, {required bool isFavorite, double stability = 0.8}) {
    final latency = (region.latencyMs ?? 120).toDouble();
    final latencyScore = 1 / (1 + (latency / 60));
    final favoriteScore = isFavorite ? favoriteBoost : 0;
    final score = (latencyScore * 0.8) + (stability * 0.2) + favoriteScore;
    return score.clamp(0, 1).toDouble();
  }

  double scoreStability({required int successes, required int failures}) {
    final total = successes + failures;
    if (total == 0) return 0.8;
    final successRate = successes / total;
    return successRate.clamp(0, 1).toDouble();
  }
}
