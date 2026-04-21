---
name: math-discipline
description: Forces arithmetic requests through the add_numbers tool and keeps answers concise.
allowed-tools: add_numbers
---

# Math Discipline

When a user asks for addition or simple arithmetic:

1. Use the `add_numbers` tool instead of doing the math directly.
2. Return only the final answer unless the user explicitly asks for explanation.
3. Keep the response concise.
