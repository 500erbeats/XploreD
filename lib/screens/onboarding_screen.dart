import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';

/// Dreistufiger Onboarding-Flow. Zentrale Idee: JEDER System-Permission-
/// Dialog wird von einer eigenen, verständlichen Erklärungs-Seite eingeleitet
/// - nie taucht ein iOS/Android-Dialog kommentarlos auf.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _settings = SettingsService();

  int _page = 0;
  static const _pageCount = 3;

  void _next() {
    if (_page < _pageCount - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _requestWhenInUse() async {
    final permission = await LocationService.instance.requestWhenInUsePermission();
    final granted = permission.name == 'whileInUse' || permission.name == 'always';

    if (granted) {
      _next();
    } else if (mounted) {
      _showDeniedHint(
        'Ohne diese Berechtigung kann die App keine Karte aufdecken. Du '
        'kannst später jederzeit in den Systemeinstellungen zustimmen.',
      );
    }
  }

  Future<void> _requestAlways() async {
    await LocationService.instance.requestAlwaysPermission();
    await _settings.setOnboardingCompleted(true);
    widget.onFinished();
  }

  Future<void> _skipBackgroundAndFinish() async {
    await _settings.setOnboardingCompleted(true);
    widget.onFinished();
  }

  void _showDeniedHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ProgressDots(current: _page, total: _pageCount),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _IntroPage(onNext: _next),
                  _WhenInUsePermissionPage(onGrant: _requestWhenInUse),
                  _AlwaysPermissionPage(
                    onGrant: _requestAlways,
                    onSkip: _skipBackgroundAndFinish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? Colors.blueAccent : Colors.grey[700],
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

/// Seite 1: erklärt das Kernkonzept der App, noch ganz ohne Permission-Bezug.
class _IntroPage extends StatelessWidget {
  final VoidCallback onNext;
  const _IntroPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.explore,
      iconColor: Colors.blueAccent,
      title: 'Entdecke deine Welt',
      body:
          'XploreD zeigt dir eine Karte, die zunächst im Nebel liegt. Je '
          'mehr du dich in der echten Welt bewegst, desto mehr davon deckst '
          'du dauerhaft auf - so wie in einem Erkundungsspiel, nur mit '
          'deiner echten Umgebung.',
      buttonLabel: 'Weiter',
      onPressed: onNext,
    );
  }
}

/// Seite 2: erklärt WARUM Standortzugriff nötig ist, BEVOR der System-Dialog
/// erscheint. Der Button löst erst danach den echten Request aus.
class _WhenInUsePermissionPage extends StatelessWidget {
  final VoidCallback onGrant;
  const _WhenInUsePermissionPage({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.location_on,
      iconColor: Colors.greenAccent,
      title: 'Standortzugriff',
      body:
          'Um die Karte um dich herum aufzudecken, braucht die App deinen '
          'Standort. Das passiert komplett lokal auf deinem Gerät - deine '
          'Position wird niemals an einen Server übertragen.\n\n'
          'Im nächsten Dialog fragt dein Betriebssystem danach - bitte '
          'wähle dort "Beim Verwenden der App erlauben" oder ähnlich.',
      buttonLabel: 'Standortzugriff erlauben',
      onPressed: onGrant,
    );
  }
}

/// Seite 3: erklärt den Hintergrund-Zugriff separat, mit expliziter
/// Möglichkeit, das für später zu überspringen statt hart einzufordern.
class _AlwaysPermissionPage extends StatelessWidget {
  final VoidCallback onGrant;
  final VoidCallback onSkip;
  const _AlwaysPermissionPage({required this.onGrant, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.travel_explore,
      iconColor: Colors.amber,
      title: 'Auch unterwegs erkunden',
      body:
          'Damit die Karte auch aufgedeckt wird, während du z.B. Auto fährst '
          'und die App nicht offen hast, braucht es zusätzlich "Immer '
          'erlauben". Das ist optional - ohne funktioniert die App, deckt '
          'aber nur auf, während sie geöffnet ist.\n\n'
          'Im nächsten Dialog wähle "Immer erlauben", falls du unterwegs '
          'automatisch erkunden möchtest.',
      buttonLabel: 'Immer erlauben aktivieren',
      onPressed: onGrant,
      secondaryLabel: 'Später entscheiden',
      onSecondaryPressed: onSkip,
    );
  }
}

class _OnboardingPageLayout extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  const _OnboardingPageLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 88, color: iconColor),
          const SizedBox(height: 32),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[300], height: 1.5),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSecondaryPressed, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}
