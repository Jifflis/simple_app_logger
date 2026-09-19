import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simple_app_logger/simple_app_logger.dart';

const apiKey = String.fromEnvironment('APP_LOGGER_API_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LoggerExampleApp());
}

class LoggerExampleApp extends StatelessWidget {
  const LoggerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple App Logger Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2457d6)),
        useMaterial3: true,
      ),
      home: const LoggerExamplePage(),
    );
  }
}

class LoggerExamplePage extends StatefulWidget {
  const LoggerExamplePage({super.key});

  @override
  State<LoggerExamplePage> createState() => _LoggerExamplePageState();
}

class _LoggerExamplePageState extends State<LoggerExamplePage>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController(
    text: 'Hello from the example app',
  );
  final _tagController = TextEditingController(text: 'example');
  final _pushTokenController = TextEditingController();

  bool _initializing = true;
  bool _ready = false;
  bool _busy = false;
  String _status = 'Preparing local logger storage…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeLogger());
  }

  Future<void> _initializeLogger() async {
    if (apiKey.isEmpty) {
      setState(() {
        _initializing = false;
        _status = 'Missing APP_LOGGER_API_KEY. See the run command below.';
      });
      return;
    }

    try {
      await SimpleAppLogger.init(
        key: apiKey,
        batchSize: 10,
        flushInterval: const Duration(seconds: 10),
        maxQueuedLogs: 1000,
        captureUnhandledError: true,
        captureNativeCrashes: true,
        apiLog: (message) => debugPrint(message),
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _ready = true;
        _status = 'Logger ready. Instance: ${SimpleAppLogger.getInstanceId()}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Initialization failed: $error';
      });
    }
  }

  Future<void> _execute(
    String successMessage,
    Future<void> Function() operation,
  ) async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (!mounted) return;
      setState(() => _status = successMessage);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Operation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _log(String level) async {
    final message = _messageController.text.trim();
    final tag = _tagController.text.trim();
    if (message.isEmpty) {
      setState(() => _status = 'Enter a log message first.');
      return;
    }

    await _execute('$level log added to the local queue.', () {
      return switch (level) {
        'Info' => SimpleAppLogger.info(message, tag: tag),
        'Warning' => SimpleAppLogger.warning(message, tag: tag),
        _ => SimpleAppLogger.error(message, tag: tag),
      };
    });
  }

  Future<void> _checkReviewStatus() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    final shouldReview = await SimpleAppLogger.shouldReview();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = shouldReview
          ? 'The backend says this instance should request a review.'
          : 'No review request is currently needed.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ready &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      unawaited(SimpleAppLogger.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _tagController.dispose();
    _pushTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple App Logger'),
        actions: [
          IconButton(
            tooltip: 'Flush queued data',
            onPressed: !_ready || _busy
                ? null
                : () => _execute(
                    'Flush completed. Offline data remains queued.',
                    SimpleAppLogger.flush,
                  ),
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_initializing || _busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 14, top: 2),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Icon(
                        _ready ? Icons.check_circle : Icons.info_outline,
                        color: _ready
                            ? Colors.green
                            : theme.colorScheme.primary,
                      ),
                    ),
                  Expanded(child: SelectableText(_status)),
                ],
              ),
            ),
          ),
          if (apiKey.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('Run with an API key:'),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: SelectableText(
                  'flutter run --dart-define=APP_LOGGER_API_KEY=your-key',
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Create a log', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagController,
            decoration: const InputDecoration(
              labelText: 'Tag (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: !_ready || _busy ? null : () => _log('Info'),
                icon: const Icon(Icons.info_outline),
                label: const Text('Info'),
              ),
              FilledButton.tonalIcon(
                onPressed: !_ready || _busy ? null : () => _log('Warning'),
                icon: const Icon(Icons.warning_amber),
                label: const Text('Warning'),
              ),
              FilledButton.tonalIcon(
                onPressed: !_ready || _busy ? null : () => _log('Error'),
                icon: const Icon(Icons.error_outline),
                label: const Text('Error'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Other SDK operations', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: !_ready || _busy
                    ? null
                    : () => _execute(
                        'Device metadata update requested.',
                        () => SimpleAppLogger.updateDevice({
                          'name': 'Logger example device',
                          'language': 'en',
                        }),
                      ),
                icon: const Icon(Icons.devices),
                label: const Text('Update device'),
              ),
              OutlinedButton.icon(
                onPressed: !_ready || _busy
                    ? null
                    : () => _execute(
                        'Custom field update requested.',
                        () => SimpleAppLogger.setCustomField(
                          fieldName: 'sample_plan',
                          value: 'developer',
                        ),
                      ),
                icon: const Icon(Icons.data_object),
                label: const Text('Set custom field'),
              ),
              OutlinedButton.icon(
                onPressed: !_ready || _busy ? null : _checkReviewStatus,
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Check review status'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pushTokenController,
            decoration: InputDecoration(
              labelText: 'Push token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Send push token',
                onPressed: !_ready || _busy
                    ? null
                    : () {
                        final token = _pushTokenController.text.trim();
                        if (token.isEmpty) {
                          setState(() => _status = 'Enter a push token first.');
                          return;
                        }
                        unawaited(
                          _execute(
                            'Push token update requested.',
                            () => SimpleAppLogger.upsertPushToken(token: token),
                          ),
                        );
                      },
                icon: const Icon(Icons.send),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Try turning off network connectivity, add several logs, then '
            'restore connectivity or press the upload button. Queued logs are '
            'kept locally until the backend acknowledges them.',
          ),
        ],
      ),
    );
  }
}
