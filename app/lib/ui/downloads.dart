import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'detail.dart';
import 'widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final jobs = session.jobs;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 22, 28, 12),
            child: Text('下载', style: TextStyle(fontSize: 26)),
          ),
          const Divider(height: 1, color: InkColors.line),
          Expanded(
            child: jobs.isEmpty
                ? const QuietMessage(title: '没有下载任务', detail: '从详情页开始下载。进度和未完成的页会留下来，可以继续。')
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: InkColors.line),
                    itemBuilder: (context, index) => _JobRow(job: jobs[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: job.albumId))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(_status(job.status), style: const TextStyle(color: InkColors.mute, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ProgressRule(value: job.active && job.total == 0 ? 0 : job.fraction),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.total > 0 ? '${job.done}/${job.total}  ${job.message}' : job.message,
                    style: const TextStyle(color: InkColors.dim, fontSize: 12),
                  ),
                ),
                if (job.active)
                  TextButton(
                    onPressed: () async {
                      await session.api.pause(job.albumId);
                      await session.refreshJobs();
                    },
                    child: const Text('暂停'),
                  )
                else if (job.status != 'complete')
                  TextButton(
                    onPressed: () async {
                      await session.api.resume(job.albumId);
                      await session.refreshJobs();
                    },
                    child: const Text('继续'),
                  ),
                if (job.status != 'complete')
                  TextButton(
                    onPressed: () async {
                      await session.api.cancel(job.albumId);
                      await session.refreshJobs();
                    },
                    child: const Text('取消'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _status(String status) {
    switch (status) {
      case 'running':
        return '下载中';
      case 'queued':
        return '排队';
      case 'paused':
        return '已暂停';
      case 'complete':
        return '完成';
      case 'error':
        return '有失败页';
      case 'canceled':
        return '已取消';
      default:
        return status;
    }
  }
}
