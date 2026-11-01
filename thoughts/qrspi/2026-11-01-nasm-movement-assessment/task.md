# Task

Incorporate the trainer's NASM movement assessment form (`nasm-assessment-form-p1.jpeg`, copied from
`IMG_4699.jpeg` in the repo root) into TrainMe, so client intake and evaluation are captured in the app
instead of on paper. Page 1 holds two tests. The **Overhead Squat Test** records compensations from three
views. Anterior covers foot turns out and knee moves in/out, each scored right/left. Lateral covers
excessive forward lean, low back arches, low back rounds and arms fall forward, scored yes/no. Posterior
covers heel rises, foot flattens and asymmetrical weight shift, scored right/left. The test also has a
"Modified" section for heels-elevated and arms-down retests across feet/knees/LPHC/upper body, plus notes.
The **Single Leg Squat Test** scores right and left legs separately for foot flattens, knee in/out, hip
hike/drop and inward/outward trunk rotation, plus notes. Each assessment is dated per client, so
re-assessments can be compared over time.

**Scope clarification (user, 2026-11-01):** do not build this as something to import (no scanning,
OCR, photo/PDF attachment or file import of the paper form). Build the assessment natively in the app as
something the trainer configures and fills in for a client.

**Scope expansion (user, 2026-11-01):**
1. Use the form as a jumping-off point for the full set of data a trainer needs about a **new client**
   (intake/evaluation). That covers health screening such as PAR-Q-style questions, medical history,
   medications, emergency contact, date of birth and similar items, alongside the movement assessment.
2. Add an **insurance / liability waiver** form that the trainer can **send to new clients**. The app
   is local-only with no backend (PRD §1, §10). How the waiver is sent, signed and recorded back in the
   app is a Design question. The waiver text is a template the trainer must have reviewed by their own
   counsel or insurer; the app must not present it as legal advice.

The form says "1/2", and page 2 is not in the repo yet. Ask the user for it before Design.
