# Chapter Layout

Each numbered chapter contains a Compose overlay and a README. The numbered
overlays are not standalone files by design. `scripts/compose-stage.sh` loads
them in numeric order, making the dependency between lessons explicit and
preserving the whole lab as it grows.

Every chapter README has four useful sections:

- **Goal**: the concept being introduced;
- **Adds**: the change from the previous chapter;
- **Checkpoint**: the observation the learner must be able to explain;
- **Break it**: a controlled failure experiment.

Chapter `05b` is an alternate standalone topology. It uses the same runner
commands but intentionally does not load the six-network Chapter 05 stack.

Chapter overlays should remain small. Put reusable images and runtime logic in
the chapter where they are first introduced, then point later overlays at that
asset rather than silently changing an earlier lesson.

Each chapter also contains `diagram.dot`, `diagram.svg`, and `diagram.png`.
Read the diagram before running the checkpoint, then use the solid, dashed, and
dotted edges to predict what should work and what should fail. Concept
definitions and the complete notation are in `GLOSSARY.md`.
