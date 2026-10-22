enum FiscalizationMode { automatic, fiscal, skip }

String fiscalizationModeToJson(FiscalizationMode mode) => mode.name;

FiscalizationMode? fiscalizationModeFromJson(dynamic value) => switch (value) {
      'automatic' => FiscalizationMode.automatic,
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
  if (selected == FiscalizationMode.fiscal) return FiscalizationMode.fiscal;
  return cartHasMarkedProducts
      ? FiscalizationMode.automatic
      : FiscalizationMode.skip;
}
