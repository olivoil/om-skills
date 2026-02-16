# People Context

## Client/Project Associations

| Person | Project | Typical Meeting Type |
|--------|---------|---------------------|
| Russell Cummings | Technomic | Meeting: Client Meeting - US |
| Bhrugen | Technomic | Meeting: Client Meeting - US |
| Eric | Technomic | Meeting: Client Meeting - US |
| Allison DeWitt | Technomic | Meeting: Client Meeting - US |

## Internal Team (EXSQ)

| Person | Context | Typical Meeting Type |
|--------|---------|---------------------|
| Chris | AI Upskill mentor | 1:1 Meeting |
| Lisa Carolan | AI Upskill program | Team/Company Meeting |
| Sridhar | AI Upskill program | Team/Company Meeting |
| Terah Stephens | AI Upskill (T3 Touch Base) | Team/Company Meeting |
| Vaibhav | AI Upskill | Team/Company Meeting |

## EWG Team

| Person | Context | Typical Meeting Type |
|--------|---------|---------------------|
| Joy Jiang | EWG audit/meetings | Meeting: Client Meeting - US |
| Don Schminke | EWG sync | Meeting: Client Meeting - US |

---

## Calendar Meeting Patterns

These patterns are used to match Outlook calendar events to Intervals projects.
When the Outlook calendar integration is active, Claude matches events by subject
and attendees against these patterns and the people associations above.

| Calendar Meeting Name | Project | Work Type |
|-----------------------|---------|-----------|
| Technomic Scrum | Ignite Application Development & Support | Meeting: Internal Stand Up - US |
| Technomic-EXSQ Weekly Touchbase | Ignite Application Development & Support | Meeting: Client Meeting - US |
| Weekly EX2 <> EWG Sync | EWG Feature Enhancement Addendum (20250047) | Meeting: Client Meeting - US |
| AI Upskilling Follow Up Session | Meeting | Team/Company Meeting |
| T3 Touch Base | Meeting | Team/Company Meeting |

**Attendee-based inference**: If a calendar event doesn't match any subject pattern,
Claude checks the attendee list against the people tables above to infer the project.
For example, a meeting with "Russell Cummings" → Technomic → Ignite Application Development & Support.
