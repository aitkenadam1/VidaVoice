import 'package:flutter/material.dart';

import '../services/first_week_plan_service.dart';

/// Guided 7-day modeling plan, shown in the Caregiver screen.
///
/// Each day pairs one research-backed habit with a concrete "try it today"
/// prompt and a done checkbox. Progress is stored per communicator profile.
class FirstWeekPlanSection extends StatefulWidget {
  const FirstWeekPlanSection({
    super.key,
    required this.profileId,
    required this.profileName,
  });

  final String profileId;
  final String profileName;

  @override
  State<FirstWeekPlanSection> createState() => _FirstWeekPlanSectionState();
}

class _FirstWeekPlanSectionState extends State<FirstWeekPlanSection> {
  final FirstWeekPlanService _plan = FirstWeekPlanService();
  Set<int> _done = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(FirstWeekPlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() => _loaded = false);
    await _plan.load(widget.profileId);
    if (!mounted) return;
    setState(() {
      _done = _plan.doneDays(widget.profileId);
      _loaded = true;
    });
  }

  Future<void> _toggle(int day, bool value) async {
    await _plan.setDone(widget.profileId, day, value);
    if (!mounted) return;
    setState(() {
      _done = _plan.doneDays(widget.profileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _done.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'First-week plan',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A guided first week for ${widget.profileName}\u2019s '
                  'communication partners. One habit per day \u2014 check each '
                  'off as you practice it.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: doneCount / firstWeekPlan.length,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$doneCount of ${firstWeekPlan.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (doneCount == firstWeekPlan.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Icon(Icons.celebration_outlined, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Week complete! Keep modeling every day \u2014 '
                            'the habits are the whole game.',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!_loaded)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else
          for (final day in firstWeekPlan)
            _dayCard(context, day, _done.contains(day.day)),
      ],
    );
  }

  Widget _dayCard(BuildContext context, PlanDay day, bool done) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: done
                  ? Colors.green
                  : Theme.of(context).colorScheme.primaryContainer,
              child: done
                  ? const Icon(Icons.check, color: Colors.white)
                  : Text(
                      '${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Day ${day.day}: ${day.title}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(day.body, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(
                          context,
                        ).style.copyWith(fontSize: 13),
                        children: [
                          const TextSpan(
                            text: 'Try it today: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: day.tryIt),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: done,
              onChanged: (v) => _toggle(day.day, v ?? false),
            ),
          ],
        ),
      ),
    );
  }
}
