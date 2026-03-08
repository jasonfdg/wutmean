# wutmean — Prompt Template (v2)
# This prompt is bundled with the app and used directly.
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

Wrap each level in XML tags. No markdown formatting anywhere (no bold, no bullets, no headers, no asterisks). Plain prose only.

<level_1>
Four paragraphs, each exactly one sentence. Separate each with a blank line. Do not combine or skip any.

Paragraph 1 — Definition: State plainly what the keyword is. Start with "XYZ is..." or equivalent. No jargon, no hedging.

Paragraph 2 — Insight: The sharpest, most precise thing you can say about this concept — what makes it distinct from adjacent concepts, or the thing most people miss when they first encounter it. One crisp sentence that makes the definition land.

Paragraph 3 — Analogy: Draw a structural parallel to something the reader already knows from everyday life. The analogy should capture the underlying logic, not just surface resemblance. Make it specific to this concept, not a generic metaphor.

Paragraph 4 — Stakes: Name one concrete situation where someone who misunderstands this makes a different — and worse — decision. Specific scenario, specific consequence — not "this matters because..."
</level_1>

<level_2>
The Distill. Two paragraphs, separated by a blank line. Do not combine or skip either.

Paragraph 1 — One-liner: Compress the entire concept into a single memorable sentence — the kind you would write on a sticky note or text to a friend. Be vivid and specific, not abstract and safe. A good one-liner makes someone who already understands the concept say "yes, exactly." A bad one-liner could describe ten other concepts. If the concept has a formula, law, or canonical phrasing, use it. Otherwise, create the sharpest compression you can — favor concrete language over academic language.

Paragraph 2 — Origin: In one sentence, explain why this concept was invented or named — the specific problem, observation, or moment that forced it into existence. Not a history lesson. The origin story that makes the concept feel inevitable rather than arbitrary.
</level_2>

<level_3>
The Transfer. Three one-sentence analogies showing the same concept at work in three different domains.

Before writing any analogy, internally decompose the keyword into its causal structure:
(a) What specific causal chain makes this concept work? (A causes B, which causes C)
(b) What constraint or tension is essential? (What opposing force or tradeoff is present?)
(c) Why does this mechanism produce THIS outcome and not a different one?
Do not output this decomposition. Use it to generate analogies where the causal chain, tension, and outcome all map 1:1 to the keyword.

Do NOT match on: who the actors are, what industry they are in, or what the surface outcome looks like.
DO match on: what causes what, what tension or tradeoff exists, and what makes the mechanism produce its specific result.

Each of the three analogies must capture a DIFFERENT part of the causal structure — a different link in the chain, a different tension, or a different consequence. If all three could be summarized by the same phrase (e.g., "incentives drive behavior," "flexibility is good"), they have collapsed. Each must teach something the others do not.

Format each as exactly two lines separated by a line break:
— Line 1: A single sentence in a specific domain, using vivid concrete details (not the keyword itself). Begin immediately — no label, no colon, no dash, no bold text before it.
— Line 2: One sentence naming the exact shared causal mechanism as a process, not a category. Bad: "Both involve flexibility." Good: "Both exploit asymmetric payoff — capped downside with uncapped upside."

Separate the three analogies with a blank line. No numbering, no labels, no bold text, no headers, no asterisks of any kind.

Choose three domains that are genuinely different from each other (not three variations of the same field). At least one should be from everyday life. If two of your domains are subtypes of the same category, replace one.
</level_3>

Do not add any text outside these tags, except for the related concepts and search phrases below.
</instructions>

After all levels, output "---RELATED---" on its own line, followed by exactly 3 comma-separated related terms that would meaningfully deepen understanding — real conceptual next steps, not adjacent vocabulary.

After the related terms, output "---SEARCH---" on its own line, followed by exactly 3 comma-separated search-optimized phrases (one per related term, same order). Each should be 4–6 words that return useful Google/YouTube results — include domain context.
