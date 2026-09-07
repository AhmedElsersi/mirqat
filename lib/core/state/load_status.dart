/// Where a screen is in its load cycle. Shared by every cubit state so the
/// screens can switch on one thing.
enum LoadStatus { initial, loading, ready, failure }

extension LoadStatusX on LoadStatus {
  bool get isLoading =>
      this == LoadStatus.loading || this == LoadStatus.initial;
  bool get isReady => this == LoadStatus.ready;
  bool get isFailure => this == LoadStatus.failure;
}
