import { NextRequest, NextResponse } from 'next/server';

const SYSTEM_PROMPT = `You are an AI golf caddy shot parser. The golfer will describe their shots in natural language, and you must extract structured data.

Return ONLY valid JSON matching this schema:
{
  "shots": [
    {
      "shotNumber": number,
      "club": string | null,       // one of: driver, 3-wood, 5-wood, 7-wood, 2-hybrid, 3-hybrid, 4-hybrid, 5-hybrid, 2-iron through 9-iron, pw, gw, sw, lw, putter
      "distanceYards": number | null,
      "result": string | null,     // one of: fairway, rough, deep-rough, bunker, water, ob, green, fringe, trees, recovery, holed
      "shape": string | null,      // one of: straight, draw, fade, hook, slice, push, pull
      "isPenalty": boolean,
      "isPutt": boolean
    }
  ],
  "putts": number | null,
  "totalStrokes": number | null,
  "fairwayHit": boolean | null,
  "greenInRegulation": boolean | null,
  "notes": string | null,
  "confidence": number            // 0.0 to 1.0
}

Rules:
- If the golfer just says a number (like "4"), that's their total strokes for the hole
- "par", "bogey", "birdie", "eagle", "double", "triple" are score names relative to the hole's par
- If they describe individual shots (e.g., "driver 260 fairway, 8 iron on the green, 2 putts"), create shot entries
- Set isPutt=true for putts, isPenalty=true for penalty strokes
- Fairway hit only applies to par 4 and par 5 holes (tee shot)
- GIR means reaching the green in par minus 2 strokes
- Be generous in interpretation — golfers speak casually
- confidence should reflect how certain you are about the parse`;

export async function POST(request: NextRequest) {
  const apiKey = process.env.ANTHROPIC_API_KEY;

  if (!apiKey) {
    return NextResponse.json({ error: 'API key not configured' }, { status: 500 });
  }

  const { input, context } = await request.json();

  const userMessage = `Hole ${context.holeNumber}, Par ${context.par}${context.yardage ? `, ${context.yardage} yards` : ''}.
Current shot number: ${context.currentShotNumber}.

Golfer says: "${input}"`;

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 512,
        system: SYSTEM_PROMPT,
        messages: [{ role: 'user', content: userMessage }],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error('Anthropic API error:', errText);
      return NextResponse.json({ error: 'AI parse failed' }, { status: 502 });
    }

    const data = await response.json();
    const text = data.content?.[0]?.text ?? '';

    // Extract JSON from the response
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      return NextResponse.json({ error: 'No JSON in response' }, { status: 502 });
    }

    const parsed = JSON.parse(jsonMatch[0]);
    return NextResponse.json(parsed);
  } catch (err) {
    console.error('Shot parse error:', err);
    return NextResponse.json({ error: 'Parse failed' }, { status: 500 });
  }
}
