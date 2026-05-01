import os
import sys
from openai import OpenAI


def main():
    # Configuration loaded from environment or defaults
    base_url = os.environ.get("LLM_BASE_URL", "http://localhost:8000/v1")
    api_key = os.environ.get("LLM_API_KEY", os.environ.get("VLLM_API_KEY", "change-me"))
    model = os.environ.get("LLM_MODEL", "llama-3.3-70b")

    client = OpenAI(
        base_url=base_url,
        api_key=api_key,
    )

    print(f"Connecting to: {base_url}")
    print(f"Model: {model}")
    print("")

    # List available models
    print("Available models:")
    try:
        models = client.models.list()
        for m in models.data:
            print(f"  - {m.id}")
    except Exception as e:
        print(f"  Error: {e}")
        sys.exit(1)

    print("")

    # Non-streaming chat completion
    print("=" * 50)
    print("Non-streaming chat completion")
    print("=" * 50)

    messages = [
        {"role": "system", "content": "You are a helpful, concise assistant."},
        {"role": "user", "content": "What are 3 practical uses for a local LLM server?"},
    ]

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=256,
            temperature=0.7,
        )
        print(f"\nAssistant: {response.choices[0].message.content}")
        print(f"\nUsage: {response.usage.prompt_tokens} prompt + {response.usage.completion_tokens} completion = {response.usage.total_tokens} tokens")
    except Exception as e:
        print(f"Error: {e}")
        return

    print("")

    # Streaming chat completion
    print("=" * 50)
    print("Streaming chat completion")
    print("=" * 50)

    messages.append({"role": "assistant", "content": response.choices[0].message.content})
    messages.append({"role": "user", "content": "Summarize your answer in one sentence."})

    try:
        stream = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=100,
            temperature=0.7,
            stream=True,
        )

        print("\nAssistant: ", end="", flush=True)
        for chunk in stream:
            if chunk.choices[0].delta.content:
                print(chunk.choices[0].delta.content, end="", flush=True)
        print("\n")
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
