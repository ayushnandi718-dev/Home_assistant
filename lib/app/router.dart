import 'package:aura_hub/app/app_shell.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/ai/presentation/ai_page.dart';
import 'package:aura_hub/features/automations/presentation/automations_page.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_page.dart';
import 'package:aura_hub/features/devices/presentation/devices_page.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:aura_hub/features/display/presentation/display_studio_page.dart';
import 'package:aura_hub/features/family/presentation/family_directory_page.dart';
import 'package:aura_hub/features/firmware/presentation/firmware_page.dart';
import 'package:aura_hub/features/integrations/presentation/integrations_page.dart';
import 'package:aura_hub/features/notifications/presentation/notifications_page.dart';
import 'package:aura_hub/features/profiles/presentation/profiles_page.dart';
import 'package:aura_hub/features/settings/presentation/settings_page.dart';
import 'package:aura_hub/features/voice_audio/presentation/voice_audio_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (BuildContext context, GoRouterState state) =>
                const DashboardPage(),
          ),
          GoRoute(
            path: AppRoutes.devices,
            builder: (BuildContext context, GoRouterState state) =>
                const DevicesPage(),
          ),
          GoRoute(
            path: AppRoutes.familyDirectory,
            builder: (BuildContext context, GoRouterState state) =>
                const FamilyDirectoryPage(),
          ),
          GoRoute(
            path: AppRoutes.profiles,
            builder: (BuildContext context, GoRouterState state) =>
                const ProfilesPage(),
          ),
          GoRoute(
            path: AppRoutes.displayStudio,
            builder: (BuildContext context, GoRouterState state) =>
                const DisplayStudioPage(),
          ),
          GoRoute(
            path: AppRoutes.voiceAudio,
            builder: (BuildContext context, GoRouterState state) =>
                const VoiceAudioPage(),
          ),
          GoRoute(
            path: AppRoutes.integrations,
            builder: (BuildContext context, GoRouterState state) =>
                const IntegrationsPage(),
          ),
          GoRoute(
            path: AppRoutes.ai,
            builder: (BuildContext context, GoRouterState state) =>
                const AiPage(),
          ),
          GoRoute(
            path: AppRoutes.automations,
            builder: (BuildContext context, GoRouterState state) =>
                const AutomationsPage(),
          ),
          GoRoute(
            path: AppRoutes.diagnostics,
            builder: (BuildContext context, GoRouterState state) =>
                const DiagnosticsPage(),
          ),
          GoRoute(
            path: AppRoutes.notifications,
            builder: (BuildContext context, GoRouterState state) =>
                const NotificationsPage(),
          ),
          GoRoute(
            path: AppRoutes.firmware,
            builder: (BuildContext context, GoRouterState state) =>
                const FirmwarePage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.explore_off_outlined,
                size: 42, color: AuraColors.textSecondary),
            const SizedBox(height: AuraSpace.md),
            Text('Page not found',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AuraSpace.xs),
            Text(
              'This route is not part of ${AppInfo.name}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AuraSpace.lg),
            FilledButton(
              onPressed: () => context.go(AppRoutes.dashboard),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
