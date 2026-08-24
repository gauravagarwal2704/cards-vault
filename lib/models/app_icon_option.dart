class AppIconOption {
  const AppIconOption({
    required this.id,
    required this.label,
    required this.description,
    required this.assetPath,
    this.isThreeDimensional = false,
  });

  final String id;
  final String label;
  final String description;
  final String assetPath;
  final bool isThreeDimensional;
}

class AppIconCatalog {
  AppIconCatalog._();

  static const threeDimensional = AppIconOption(
    id: 'three_d',
    label: '3D',
    description: 'Dimensional violet',
    assetPath: 'assets/branding/app_icon_3d.png',
    isThreeDimensional: true,
  );

  static const options = <AppIconOption>[
    threeDimensional,
    AppIconOption(
      id: 'purple',
      label: 'Purple',
      description: 'Royal violet',
      assetPath: 'assets/branding/app_icon_purple.png',
    ),
    AppIconOption(
      id: 'multicolor',
      label: 'Multicolor',
      description: 'Indigo and teal',
      assetPath: 'assets/branding/app_icon_multicolor.png',
    ),
    AppIconOption(
      id: 'ocean',
      label: 'Ocean',
      description: 'Navy and cyan',
      assetPath: 'assets/branding/app_icon_ocean.png',
    ),
    AppIconOption(
      id: 'emerald',
      label: 'Emerald',
      description: 'Green and mint',
      assetPath: 'assets/branding/app_icon_emerald.png',
    ),
    AppIconOption(
      id: 'sunset',
      label: 'Sunset',
      description: 'Plum and orange',
      assetPath: 'assets/branding/app_icon_sunset.png',
    ),
    AppIconOption(
      id: 'red',
      label: 'Red',
      description: 'Burgundy and crimson',
      assetPath: 'assets/branding/app_icon_red.png',
    ),
  ];

  static AppIconOption findById(String? id) => options.firstWhere(
    (option) => option.id == id,
    orElse: () => threeDimensional,
  );
}
