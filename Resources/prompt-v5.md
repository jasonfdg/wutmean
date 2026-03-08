# Instant Explain — Prompt Template (v5)
# Edit this file to customize how explanations are generated.
# Place your customized version at: ~/.config/instant-explain/prompt.md
#
# Placeholders:
#   {{TEXT}}      — the keyword/phrase the user highlighted
#   {{CONTEXT}}   — surrounding context from the source document (if available)
#   {{LANGUAGE}}  — output language (English or Chinese)

## Standard Explanation

Respond entirely in {{LANGUAGE}}.

<keyword>{{TEXT}}</keyword>
{{CONTEXT}}

<instructions>
Explain the keyword at three levels. Use the context only to determine the most relevant meaning and domain of the keyword — never reference, quote, or acknowledge the context in your response.

Wrap each level in XML tags. No markdown formatting anywhere (no bold, no bullets, no headers, no asterisks). Plain prose only, except Level 3 uses the structured example format described below.

<level_1>
Four sentences. Each serves a distinct function — do not combine or skip any.

Sentence 1 — Definition: State plainly what the keyword is. Start with "XYZ is..." or equivalent. No jargon, no hedging.

Sentence 2 — Insight: The sharpest, most precise thing you can say about this concept — what makes it distinct from adjacent concepts, or the thing most people miss when they first encounter it. One crisp sentence that makes the definition land.

Sentence 3 — Analogy: Draw a structural parallel to something the reader already knows from everyday life. The analogy should capture the underlying logic, not just surface resemblance. Make it specific to this concept, not a generic metaphor.

Sentence 4 — Stakes: Name one concrete situation where someone who misunderstands this makes a different — and worse — decision. Specific scenario, specific consequence — not "this matters because..."
</level_1>

<level_2>
The Understanding. Use refutational structure. Write as three paragraphs.

Paragraph 1: Name the most common misconception — the thing smart people consistently get wrong or conflate. Then explain exactly why that view fails.

Paragraph 2: Give the correct understanding, defining 2–3 key terms inline as you use them (not in a separate list).

Paragraph 3: The cause-effect chain that makes this concept work — what triggers it, what it produces, what changes as a result.
</level_2>

<level_3>
The Usage. Show the concept in action through three examples that let meaning emerge from use rather than from definition.

Format each example as exactly two lines separated by a line break:
— Line 1: A sentence in double quotes showing the keyword in a specific, vivid situation. Begin immediately with the opening double quote — no label, no colon, no dash, no bold text before it.
— Line 2: A plain, unquoted explanation in 1–2 sentences of what that example reveals. Not a full analysis — just the key insight it unlocks.

Separate the three examples with a blank line. No numbering, no labels, no bold text, no headers, no asterisks of any kind.

The three examples:
(1) A sentence using the keyword correctly and precisely, followed by what it reveals about the concept's internal logic.
(2) A near-miss — a sentence using an adjacent concept that people genuinely confuse with the keyword. The confusion should be understandable, not obvious. Follow with a precise explanation of what makes them different.
(3) A sentence in the same domain as the surrounding context, followed by what it reveals about the concept's scope, limits, or stakes in that domain.

Do not define the keyword first. Let the examples teach.
</level_3>

Do not add any text outside these tags, except for the related concepts and search phrases below.
</instructions>

After all levels, output "---RELATED---" on its own line, followed by exactly 3 comma-separated related terms that would meaningfully deepen understanding — real conceptual next steps, not adjacent vocabulary.

After the related terms, output "---SEARCH---" on its own line, followed by exactly 3 comma-separated search-optimized phrases (one per related term, same order). Each should be 4–6 words that return useful Google/YouTube results — include domain context.
