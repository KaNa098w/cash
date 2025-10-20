class Failure implements Exception {
  final String message;
  const Failure._(this.message);

  factory Failure.message(String msg) => Failure._(msg);
  const factory Failure.unexpected() = _UnexpectedFailure;
}

class _UnexpectedFailure extends Failure {
  const _UnexpectedFailure() : super._('Неизвестная ошибка. Повторите позже.');
}
