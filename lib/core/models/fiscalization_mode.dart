enum FiscalizationMode { fiscal, skip }

String fiscalizationModeToJson(FiscalizationMode mode) => mode.name;

FiscalizationMode? fiscalizationModeFromJson(dynamic value) => switch (value) {
      'fiscal' => FiscalizationMode.fiscal,
      'skip' => FiscalizationMode.skip,
      _ => null, // Older cached documents did not specify a mode.
    };

FiscalizationMode resolveFiscalizationMode({
  required bool enabled,
  required bool markedProductsOnly,
  required bool cartHasMarkedProducts,
  FiscalizationMode? selected,
}) {
  if (!enabled) return FiscalizationMode.skip;
  if (cartHasMarkedProducts) return FiscalizationMode.fiscal;
  return selected ?? FiscalizationMode.skip;
}
