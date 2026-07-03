import 'dart:async';

import 'package:flutter/material.dart';

class PhaseTimer extends StatefulWidget {
  const PhaseTimer({super.key, required this.timeoutAt});

  final DateTime timeoutAt;

  @override
  State<PhaseTimer> createState() => _PhaseTimerState();
}

class _PhaseTimerState extends State<PhaseTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    setState(() {
      _remaining = widget.timeoutAt.difference(DateTime.now());
      if (_remaining.isNegative) _remaining = Duration.zero;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final min = _remaining.inMinutes;
    final sec = _remaining.inSeconds % 60;
    return Chip(
      avatar: const Icon(Icons.timer, size: 16),
      label: Text('${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'),
    );
  }
}
