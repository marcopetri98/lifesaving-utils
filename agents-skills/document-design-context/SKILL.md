---
name: document-design-context
description: Consolidate a technical conversation and relevant repository code into durable Markdown documentation. Use when asked to preserve knowledge about a component, explain its implementation, record design choices and rationale, or document relevant rejected and unapproved alternatives. Support deep learning and general software engineering repositories.
---

# Document Design Context

Write a self-contained technical reference that allows a future contributor
to understand the topic, its implementation, and the reasons behind its
design without reading the original conversation.

Use the destination already established by the caller. This skill defines
how to write the document, not where to save it.

## Gather and reconcile the evidence

1. Review all available conversation context relevant to the requested topic.
   Extract requirements, constraints, explanations, decisions, corrections,
   alternatives, experiments, and unresolved questions.

2. Inspect the relevant repository code, configuration, call sites, tests,
   and existing documentation. Trace enough of the surrounding implementation
   to explain how the component actually works.

3. Reconcile the conversation with the implementation:
   - Use inspected code as evidence of current behavior.
   - Use explicit conversation decisions as evidence of intent and approval.
   - When they differ, explain the discrepancy.
   - Distinguish accepted plans from implemented behavior.

4. Preserve the recorded rationale. Do not invent motivations, trade-offs,
   approval, or experimental results. Label useful inferred explanations as
   inferences. State when a material rationale is unavailable.

5. When updating existing documentation, integrate new information into the
   appropriate sections. Correct obsolete claims, remove duplication, and
   preserve still-valid explanations and meaningful decision history.

If relevant conversation history or files are unavailable, identify the
specific gap and limit claims accordingly.

## Document structure

Adapt the following structure to the topic and repository conventions.
Merge or omit optional sections when they have no substantive content.

### 1. Purpose and scope

Explain:
- What the component or feature does.
- Which problem it solves.
- Its boundaries and responsibilities.
- The requirements and constraints that shaped its design.

Define specialized terminology and notation needed by the reader.

### 2. Current implementation

Explain the architecture and execution or data flow in a logical order.

Identify the important modules, classes, and functions, their responsibilities,
and how they interact. Cover relevant inputs, outputs, configuration,
defaults, invariants, and edge cases.

For deep learning code, include applicable details such as:
- Tensor shapes and the meaning of each dimension.
- Transformations and the forward computation.
- Parameter ownership, sharing, and initialization.
- Positional information, masking, and normalization.
- Gradient flow and training versus evaluation behavior.
- Objectives, data processing, and computational costs when relevant.

For general software engineering code, include applicable details such as:
- Interfaces and contracts.
- Data models, state, and lifecycle.
- Dependency ownership.
- Validation and error handling.
- Concurrency, persistence, and compatibility constraints.

Select details that explain the actual implementation. Do not expand these
examples into a generic tutorial or a mandatory checklist.

### 3. Design choices and rationale

For each material design choice, describe:
- The chosen approach.
- Its decision and implementation status, where clarification is needed.
- The requirement, constraint, or problem that motivated it.
- The established reason for preferring it.
- The resulting trade-offs, consequences, and limitations.

Use short subsections when a decision needs explanation. Use a table when
several choices can be compared concisely.

Preserve reasoning that cannot be recovered from reading the code alone.

### 4. Alternatives and choices not adopted

Include this section when it helps explain the current design or prevents
repeating a settled discussion.

For each relevant alternative:
- Explain what was proposed.
- Distinguish rejected, deferred, superseded, and unresolved proposals.
- Record the stated reason for rejection, deferral, or replacement.
- State when approval or a reason was not recorded.
- Include conditions for reconsideration only when established.

Do not treat silence as approval or an undecided proposal as rejection.
Existing code does not, by itself, establish explicit approval.

### 5. Validation, limitations, and open questions

Summarize relevant tests or experiments and what their evidence supports.

Distinguish tests found in the repository from tests actually run and
observed results. Record known limitations, implementation gaps, and
unresolved decisions.

Keep hypotheses and proposed follow-up work separate from established facts.
Omit this section when there is nothing substantive to report.

### 6. Code and reference pointers

Provide links to relevant repository files and name the exact symbols readers
should inspect. Use paths relative to the document and prefer stable paths
and symbol names over brittle line numbers.

Include external references only when they support the explanation.
Distinguish a published method from the repository's adaptation.

Place references inline instead of using a separate section when clearer.

## Writing principles

- Organize by concept and current state rather than conversation chronology.
- Preserve substantive knowledge while removing repetition and unrelated
  tangents.
- Make explanations understandable without access to the original chat.
- Explain both how the implementation works and why consequential choices
  were made.
- Use consistent terminology and exact code identifiers.
- Include short code excerpts, equations, tables, or diagrams only when they
  clarify a specific point.
- Verify excerpts against the implementation. Label pseudocode and
  illustrative examples.
- Avoid copying large blocks of code or including secrets and irrelevant
  personal information.
- Document discrepancies without modifying implementation code to make it
  match the narrative.

## Final review

Before finishing, verify that:
- The relevant knowledge from the available conversation and code is covered.
- Behavioral descriptions and symbol references match the inspected code.
- Rationale and approval claims have supporting evidence.
- Implemented behavior, accepted plans, inferred explanations, and unresolved
  proposals are clearly distinguishable.
- Relevant alternatives and their recorded outcomes are preserved.
- Empty headings, placeholders, duplication, and unsupported claims are removed.