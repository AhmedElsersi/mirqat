# background_downloader runs on WorkManager, and WorkManager keeps its queue in
# a Room database. Room finds the generated `WorkDatabase_Impl` by name, through
# reflection, the moment the process starts (androidx.startup) — before any Dart
# runs. R8 in full mode (AGP 9's default) sees nothing reference that class and
# strips it, and the app dies at launch with "Failed to create an instance of
# class androidx.work.impl.WorkDatabase". Room 2.5's own consumer rules predate
# full mode, so the generated databases are kept here.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
