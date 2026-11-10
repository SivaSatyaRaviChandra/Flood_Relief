/// How serious a reported flood condition is, ordered from least to worst.
library;

enum FloodSeverity {
  low('LOW', 'Low', 0),
  medium('MEDIUM', 'Medium', 1),
  high('HIGH', 'High', 2),
  critical('CRITICAL', 'Critical', 3);

  const FloodSeverity(this.code, this.label, this.weight);

  final String code;
  final String label;
  final int weight;

  static FloodSeverity? fromCode(String? code) {
    if (code == null) return null;
    for (final s in FloodSeverity.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Categorised depth of standing water, used to make reports comparable.
enum WaterDepthCategory {
  ankleDeep('ANKLE', 'Ankle deep', 0.1),
  kneeDeep('KNEE', 'Knee deep', 0.5),
  waistDeep('WAIST', 'Waist deep', 1.0),
  chestDeep('CHEST', 'Chest deep', 1.5),
  aboveHead('ABOVE_HEAD', 'Above head height', 2.0);

  const WaterDepthCategory(this.code, this.label, this.approximateMetres);

  final String code;
  final String label;

  /// Lower bound of the category in metres, used for display only.
  final double approximateMetres;

  static WaterDepthCategory? fromCode(String? code) {
    if (code == null) return null;
    for (final c in WaterDepthCategory.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
