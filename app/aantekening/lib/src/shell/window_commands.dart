/// What the window's own commands do: the tabs, the panels, going from
/// page to page, making and naming things, and the settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commands/app_command.dart';
import '../commands/command_palette.dart';
import '../commands/shortcuts.dart';
import '../editor/page_minimap.dart';
import '../look/appearance.dart';
import '../providers.dart';
import '../settings/settings_view.dart';
import '../spelling/spelling.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'sidebar_state.dart';
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
  SidebarController sidebar() => ref.read(sidebarProvider.notifier);
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

  Future<void> deletePage() async {
    final pageId = tab().pageId;
    if (pageId == null) return;
    final page = await ref.read(pageProvider(pageId).future);
    if (page == null || !context.mounted) return;
    if (await confirmDeletion(context, page)) await library().delete(page);
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
    AppCommand.previousTab: CommandAction(() => tabs().step(-1)),
    AppCommand.notebooks: CommandAction(
      () => sidebar().focus(SidebarTab.notebooks),
    ),
    AppCommand.search: CommandAction(() => sidebar().focus(SidebarTab.search)),
    AppCommand.graph: CommandAction(() => sidebar().focus(SidebarTab.graph)),
    AppCommand.togglePanel: CommandAction(() => sidebar().togglePanel()),
    AppCommand.ai: CommandAction(
      () => tabs().toggleAi(),
      enabled: () => tab().hasChoice,
    ),
    AppCommand.newPage: CommandAction(
      () => unawaited(library().createPage(sectionId: tab().sectionId!)),
      enabled: () => tab().sectionId != null,
    ),
    AppCommand.newSubpage: CommandAction(
      () => unawaited(
        library().createPage(
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
  };
}
