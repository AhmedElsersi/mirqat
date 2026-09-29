# background_downloader runs on WorkManager, and WorkManager keeps its queue in
# a Room database. Room finds the generated `WorkDatabase_Impl` by name, through
# reflection, the moment the process starts (androidx.startup) — before any Dart
# runs. R8 in full mode (AGP 9's default) sees nothing reference that class and
# strips it, and the app dies at launch with "Failed to create an instance of
# class androidx.work.impl.WorkDatabase". Room 2.5's own consumer rules predate
# full mode, so the generated databases are kept here.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# The same shape of failure, one step later. WorkManager also instantiates a
# task's InputMerger by name through reflection (`OverwritingInputMerger` for
# every ordinary task), through its no-argument constructor. work-runtime's
# own rule keeps the class but names no members, and R8 in full mode then
# drops the constructor as unused: `NoSuchMethodException:
# androidx.work.OverwritingInputMerger.<init> []`. WorkManager logs "Could not
# create Input Merger", fails the work before the worker is ever built, and a
# download sits at zero for good — in the release build only, since debug is
# not minified.
-keep class * extends androidx.work.InputMerger { <init>(); }
