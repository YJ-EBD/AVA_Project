# FlutterFlow Integration Boundary

Place FlutterFlow-derived widgets, theme adapters, or page prototypes here only after review.

Do not copy a whole FlutterFlow export over the AVA Flutter app root. AVA has custom Windows native code, Riverpod state, update logic, and backend contracts that FlutterFlow exports may overwrite.

Recommended flow:
1. Designers work in FlutterFlow.
2. FlutterFlow pushes generated code to the `flutterflow` branch on GitHub.
3. Developers pull that branch into `.flutterflow-worktree`.
4. Reviewed widgets/pages are adapted into this folder or regular AVA feature folders.
