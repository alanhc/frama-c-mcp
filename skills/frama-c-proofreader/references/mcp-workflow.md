# MCP Workflow

Use this order for normal verification:

```text
self_check {}
reload_project {files, rte: true}
check {function?, timeout?}
get_wp_goals {want: ["alarms"], function?, status?}
get_wp_goals {want: ["investigation"], marker, depth}
get_wp_goals {function, status?}
context {function, want: ["current_annotations", "function_ast"]}
inject_all_annotations {function, dry_run: true, annotations: [{kind, acsl, ...}]}
inject_all_annotations {function, annotations: [{kind, acsl, ...}]}
run_wp {functions: [function]}
check {files, smoke: true}
store_function_conclusion {function, ...}
proof_coverage {detail: "full"}
```

Stop only when `check` for the target function reports no `incomplete[]` entries, and `check {files, smoke: true}` reports neither `SMOKE_TEST_FAILED` nor `SMOKE_TEST_UNCHECKED`. `proof_coverage {detail: "full"}` then lists defined functions and their stored conclusions; there is no separate status tool.

Use a sandbox for speculative annotations:

```text
create_sandbox {function, experiment_id?}
context {function: "experiment:function", want: ["function_ast", "current_annotations"]}
inject_all_annotations {sandbox_name: "experiment:function", dry_run: true, ...}
inject_all_annotations {sandbox_name: "experiment:function", ...}
run_wp {functions: ["experiment:function"]}
get_wp_goals {function: "experiment:function"}
delete_sandbox {sandbox_name: "experiment:function"}
```

Merge only annotations that passed in the sandbox, then rerun WP on the main function.

If markers go stale after reload, refresh them with `get_wp_goals {want: ["alarms"]}` or `get_wp_goals` instead of reusing old ids.
