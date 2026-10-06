/// Window actions handed to the coordinator, which outlives every view. Its own
/// file because the coordinator names it, and `DaybookApp.swift` holds the
/// production entry point, which the fixture build leaves out.
struct WindowOpener {
    let open: (AppTab?) -> Void
    let reopen: () -> Void
}
