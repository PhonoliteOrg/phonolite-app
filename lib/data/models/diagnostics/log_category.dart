enum LogCategory {
  all('All'),
  info('Info'),
  activities('Activities'),
  warnings('Warnings'),
  errors('Errors'),
  issues('Issues'),
  debug('Debug');

  final String label;

  const LogCategory(this.label);

  String get fileName => '$name.log';
}
