# AMQM Production Attendance

## Implemented in v26
- Student QR resolves by Admission Number.
- Staff QR resolves by Staff ID.
- Day pupils are recorded at the gate by QR scanner.
- Boarding pupils remain a class-teacher attendance workflow.
- Morning deadline and grace period are configurable.
- Late status is calculated from the configured deadline.
- Manual fallback is available when a pupil forgets an ID.
- Excused absence can carry a reason.
- Attendance records preserve capture mode, time and officer metadata.
- Scanner access is administrator-controlled through each staff profile.
- Staff late and absence penalties use configurable amounts and remain separate from attendance.
- Parent SMS is represented as a queue decision but remains OFF until a real provider is connected.
- Existing attendance records are not migrated or deleted by this build.

## Production wiring still required
- Deploy database-side attendance constraints and server-side duplicate protection.
- Connect the SMS provider.
- Add true offline queue synchronization in the Android app.
- Validate the exact school's attendance policy before enabling financial penalties.
