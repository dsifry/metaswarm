# User Flows

> Define user interactions before work unit decomposition.
> Each flow must have a clear trigger, steps, and visible outcome.
> Integration work units must be created to wire components into the app shell.

## Screens

<!-- Describe each screen with a text wireframe showing layout and interactive elements -->

### Screen: Main Layout

```
┌─────────────────────────────────────┐
│ Header                              │
├──────────────┬──────────────────────┤
│ Panel A      │ Panel B              │
│              │                      │
│              │                      │
└──────────────┴──────────────────────┘
```

**Components**: _List the React/UI components that compose this screen_
**Data Flow**: _What hooks/state manage this screen's data_

## User Flows

<!-- Each flow: trigger → steps → outcome. Must map to work units. -->

### Flow: [Action Name]

| Step | User Action | System Response | Component |
|------|------------|-----------------|-----------|
| 1 | _User clicks X_ | _System does Y_ | _ComponentName_ |
| 2 | _User types Z_ | _Input validates_ | _ComponentName_ |
| 3 | _User presses Enter_ | _Item appears in list_ | _ComponentName_ |

**Error States**: _What happens on failure_
**Loading States**: _What the user sees while waiting_
**Empty States**: _What the user sees with no data_

## Integration Checklist

<!-- Verify components are wired into the app, not just exported -->

- [ ] All components rendered in the app shell (not just exported)
- [ ] All hooks connected to real data sources (API/WebSocket)
- [ ] All user flows completable end-to-end
- [ ] Error, loading, and empty states visible to the user
