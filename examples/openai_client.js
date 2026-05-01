const OpenAI = require('openai');

const client = new OpenAI({
  baseURL: process.env.LLM_BASE_URL || 'http://localhost:8000/v1',
  apiKey: process.env.LLM_API_KEY || process.env.VLLM_API_KEY || 'change-me',
});

const model = process.env.LLM_MODEL || 'llama-3.3-70b';

async function main() {
  console.log(`Connecting to: ${client.baseURL}`);
  console.log(`Model: ${model}\n`);

  // List models
  console.log('Available models:');
  const models = await client.models.list();
  for (const m of models.data) {
    console.log(`  - ${m.id}`);
  }
  console.log();

  // Chat completion
  console.log('Non-streaming chat completion');
  console.log('='.repeat(50));

  const completion = await client.chat.completions.create({
    model,
    messages: [
      { role: 'system', content: 'You are a helpful, concise assistant.' },
      { role: 'user', content: 'Write a haiku about local AI servers.' },
    ],
    max_tokens: 100,
    temperature: 0.7,
  });

  console.log(`\nAssistant: ${completion.choices[0].message.content}`);
  console.log(`\nUsage: ${JSON.stringify(completion.usage, null, 2)}\n`);

  // Streaming completion
  console.log('Streaming chat completion');
  console.log('='.repeat(50));

  const stream = await client.chat.completions.create({
    model,
    messages: [
      { role: 'system', content: 'You are a helpful, concise assistant.' },
      { role: 'user', content: 'Count from 1 to 10.' },
    ],
    max_tokens: 100,
    temperature: 0.0,
    stream: true,
  });

  process.stdout.write('\nAssistant: ');
  for await (const chunk of stream) {
    process.stdout.write(chunk.choices[0]?.delta?.content || '');
  }
  console.log('\n');
}

main().catch(console.error);
