# Instant Explain — Prompt Template (v4)
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
The Hook. Two sentences only.

Sentence 1 — Analogy: Map this concept onto something the reader already knows from everyday life. The analogy should capture the structural logic, not just a surface similarity. Start with "It's like..." or an equivalent opening.

Sentence 2 — Stakes: One concrete consequence or real-world situation where knowing this concept changes what you do or understand. Answer: "so what does this actually affect?"

No jargon. No definitions. Two sentences, nothing more.
</level_1>

<level_2>
The Understanding. Use refutational structure.

Open by naming the most common misconception about this keyword — the thing smart people consistently get wrong or conflate. Then explain why that view fails. Then give the correct understanding, defining 2–3 key terms inline as you use them (not in a separate list).

End with the cause-effect chain that makes this concept work: what triggers it, what it produces, what changes as a result.

4–5 sentences total.
</level_2>

<level_3>
The Usage. Show the concept in action through three examples that let meaning emerge from use rather than from definition.

Format each example as exactly two lines separated by a line break:
— Line 1: A sentence in double quotes showing the keyword in a specific, vivid situation.
— Line 2: A plain, unquoted explanation of what that sentence reveals about how the concept operates.

Separate the three examples with a blank line. No numbering, no labels, no headers, no asterisks.

The three examples:
(1) A sentence using the keyword correctly and precisely, followed by what it reveals about the concept's internal logic.
(2) A near-miss — a sentence that looks related but does NOT correctly use or apply the keyword — followed by a precise explanation of where it goes wrong. Make the error plausible, not obvious.
(3) A sentence in the same domain as the surrounding context, followed by what it reveals about the concept's scope, limits, or stakes in that domain.

Do not define the keyword first. Let the examples teach.
</level_3>

Do not add any text outside these tags, except for the related concepts and search phrases below.
</instructions>

After all levels, output "---RELATED---" on its own line, followed by exactly 3 comma-separated related terms that would meaningfully deepen understanding — real conceptual next steps, not adjacent vocabulary.

After the related terms, output "---SEARCH---" on its own line, followed by exactly 3 comma-separated search-optimized phrases (one per related term, same order). Each should be 4–6 words that return useful Google/YouTube results — include domain context.
