# Deliver private attachments through backend authorization

SupaNotes stores attachments as private objects and keeps the object key instead of a permanent public URL. The backend validates either an authenticated note permission or an active **Share Link** before it delivers an attachment, so revoking note access also blocks new attachment requests immediately.

## Considered Options

- Permanent public object URLs were rejected because they survive access revocation.
- Time-limited signed object URLs were rejected because they remain usable until they expire.

## Consequences

- Attachment delivery uses backend bandwidth.
- Authorization rules for note documents and attachments must remain consistent.
- Logs, errors, and responses must not disclose private object keys or share secrets.
