import json
import os
from anthropic import Anthropic

client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))

PROMPT_TEMPLATE = """Explain the following text at exactly 5 difficulty levels.

Return ONLY valid JSON, no markdown, no explanation outside the JSON:
{{
  "levels": [
    "ELI5 (1-2 sentences, like explaining to a 10-year-old)",
    "Simple (2-3 sentences, plain English for a smart non-expert)",
    "Contextual (2-3 sentences, pitched just at the edge of understanding for someone already reading technical content)",
    "Technical (2-3 sentences, precise terminology, assumes domain knowledge)",
    "Expert (2-3 sentences, assumes deep expertise, include nuance or edge cases)"
  ]
}}

Text to explain:
{text}"""

def fetch_explanations(text: str) -> list[str]:
    """
    Call Claude Haiku once, get all 5 explanation levels.
    Returns list of 5 strings. Raises on API error.
    """
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=600,
        messages=[
            {"role": "user", "content": PROMPT_TEMPLATE.format(text=text)}
        ]
    )
    raw = response.content[0].text.strip()
    data = json.loads(raw)
    return data["levels"]
