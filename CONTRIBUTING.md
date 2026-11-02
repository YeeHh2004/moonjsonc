# Contributing

Use the pinned compiler/core and commands in [DEVELOPMENT](docs/DEVELOPMENT.md).
Keep source algorithms in MoonBit and host adapters thin. Include a regression
for a concrete bug or a meaningful consumer example for a new API. Tests should
check observable semantics, original-source preservation and invalid-input
behavior; they should not merely restate implementation steps.

Update generated `.mbti` files with `moon info`, and document deliberate behavior
changes. Do not weaken reference comparisons to conceal a mismatch: add a small
reproducer, decide the intended contract and explain any divergence.

Open an issue for a substantial scope change before implementation. Contributions
must be compatible with MIT and retain applicable third-party notices. AI-assisted
work is welcome when reviewed, tested, and described accurately.
