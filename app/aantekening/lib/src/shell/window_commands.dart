/// What the window's own commands do: the tabs, the picker and the search,
/// going from page to page, making and naming things, and the settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commands/app_command.dart';
import '../commands/command_palette.dart';
import '../commands/shortcuts.dart';
import '../editor/page_minimap.dart';
import '../files/backup_settings.dart';
import '../files/bin_view.dart';
import '../look/appearance.dart';
import '../providers.dart';
import '../search/search_line.dart';
import '../settings/settings_view.dart';
import '../spelling/spelling.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'new_page_dialog.dart';
import 'picker.dart';
import 'tabs.dart';

/// The commands the window carries out, for [CommandHandlers], acting in
/// [context] through [ref].
///
/// The page editor carries out the page's own commands; everything else
/// is here.
Map<AppCommand, CommandAction> windowCommands(
  BuildContext context,
  WidgetRef ref,
) {
  TabsController tabs() => ref.read(tabsProvider.notifier);
  LibraryActions library() => ref.read(libraryActionsProvider);
  NoteTab tab() => ref.read(tabsProvider).current;

  CommandAction settings(SettingsPage page) =>
      CommandAction(() => unawaited(showSettings(context, page: page)));

  /// Goes to the page [take] gives, if it is still there.
  Future<void> travel(String? Function() take) async {
    final pageId = take();
    if (pageId == null) return;
    if (!await library().openPageId(pageId)) tabs().cancelTravel();
  }

  /// Splits the window; a new tab beside the page, with nothing chosen
  /// yet, has the picker open on it to choose a page.
  Future<void> split({required bool stacked}) async {
    tabs().split(stacked: stacked);
    if (tab().pageId == null && context.mounted) {
      await showPicker(context, ref, PickerView.library);
    }
  }

  Future<void> deletePage() async {
    final pageId = tab().pageId;
    if (pageId == null) return;
    final page = await ref.read(pageProvider(pageId).future);
    if (page == null || !context.mounted) return;
    await deleteToBin(context, ref, page);
  }

  return <AppCommand, CommandAction>{
    AppCommand.goTo: CommandAction(
      () => unawaited(showCommandPalette(context)),
    ),
    AppCommand.commands: CommandAction(
      () => unawaited(showCommandPalette(context, commands: true)),
    ),
    AppCommand.back: CommandAction(
      () => unawaited(travel(tabs().goBack)),
      enabled: () => tabs().canGoBack,
    ),
    AppCommand.forward: CommandAction(
      () => unawaited(travel(tabs().goForward)),
      enabled: () => tabs().canGoForward,
    ),
    AppCommand.previousPage: CommandAction(
      () => unawaited(library().stepPage(-1)),
      enabled: () => tab().sectionId != null,
    ),
    AppCommand.nextPage: CommandAction(
      () => unawaited(library().stepPage(1)),
      enabled: () => tab().sectionId != null,
    ),
    AppCommand.previousSection: CommandAction(
      () => unawaited(library().stepSection(-1)),
      enabled: () => tab().notebookId != null,
    ),
    AppCommand.nextSection: CommandAction(
      () => unawaited(library().stepSection(1)),
      enabled: () => tab().notebookId != null,
    ),
    AppCommand.newTab: CommandAction(() => tabs().open()),
    AppCommand.closeTab: CommandAction(() => tabs().closeShowing()),
    AppCommand.reopenTab: CommandAction(
      () => tabs().reopen(),
      enabled: () => tabs().canReopen,
    ),
    AppCommand.nextTab: CommandAction(() => tabs().step(1)),
    AppCommand.splitSideBySide: CommandAction(
      () => unawaited(split(stacked: false)),
    ),
    AppCommand.splitStacked: CommandAction(
      () => unawaited(split(stacked: true)),
    ),
    AppCommand.unsplit: CommandAction(
      () => tabs().unsplit(),
      enabled: () => ref.read(tabsProvider).beside != null,
    ),
    AppCommand.otherPane: CommandAction(
      () => tabs().toBeside(),
      enabled: () => ref.read(tabsProvider).beside != null,
    ),
    AppCommand.previousTab: CommandAction(() => tabs().step(-1)),
    AppCommand.notebooks: CommandAction(
      () => unawaited(showPicker(context, ref, PickerView.library)),
    ),
    AppCommand.search: CommandAction(
      ref.read(searchLineProvider.notifier).open,
    ),
    AppCommand.graph: CommandAction(
      () => unawaited(showPicker(context, ref, PickerView.graph)),
    ),
    AppCommand.ai: CommandAction(
      () => tabs().toggleAi(),
      enabled: () => tab().hasChoice,
    ),
    AppCommand.newPage: CommandAction(
      () => unawaited(
        createChosenPage(context, ref, sectionId: tab().sectionId!),
      ),
      enabled: () => tab().sectionId != null,
    ),
    AppCommand.newSubpage: CommandAction(
      () => unawaited(
        createChosenPage(
          context,
          ref,
          sectionId: tab().sectionId!,
          parentId: tab().pageId,
        ),
      ),
      enabled: () => tab().sectionId != null && tab().pageId != null,
    ),
    AppCommand.newSection: CommandAction(
      () => unawaited(
        createNamedSection(context, ref, notebookId: tab().notebookId!),
      ),
      enabled: () => tab().notebookId != null,
    ),
    AppCommand.newNotebook: CommandAction(
      () => unawaited(createNamedNotebook(context, ref)),
    ),
    AppCommand.renamePage: CommandAction(() {
      final pageId = tab().pageId!;
      // The title is on the page, so the page shows rather than its AI.
      tabs().updateCurrent((tab) => tab.inAi(false));
      ref.read(titleFocusProvider.notifier).request(pageId);
    }, enabled: () => tab().pageId != null),
    AppCommand.deletePage: CommandAction(
      () => unawaited(deletePage()),
      enabled: () => tab().pageId != null,
    ),
    AppCommand.pagePreview: CommandAction(
      () => ref.read(minimapProvider.notifier).toggle(),
    ),
    AppCommand.toggleDark: CommandAction(
      () => ref
          .read(appearanceProvider.notifier)
          .toggleBrightness(Theme.of(context).brightness),
    ),
    AppCommand.spelling: CommandAction(() {
      final spelling = ref.read(spellingProvider);
      ref.read(spellingProvider.notifier).setEnabled(!spelling.enabled);
    }),
    AppCommand.settings: settings(SettingsPage.appearance),
    AppCommand.keyboardShortcuts: settings(SettingsPage.keyboard),
    AppCommand.aiSettings: settings(SettingsPage.ai),
    AppCommand.dictionaries: settings(SettingsPage.spelling),
    AppCommand.files: settings(SettingsPage.files),
    AppCommand.importNotes: settings(SettingsPage.files),
    AppCommand.bin: CommandAction(() => unawaited(showBin(context))),
    AppCommand.backUpNow: CommandAction(
      () => unawaited(ref.read(backupsProvider.notifier).backUpNow()),
    ),
  };
}
