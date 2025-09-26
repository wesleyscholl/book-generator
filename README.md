# 📚 Book-Generator

Automated book authoring, editing and compilation toolkit.

This repository contains a set of shell scripts and helper tools that together can:

- Pick topics and book titles (AI-assisted)
- Generate detailed outlines
- Generate, extend and edit chapters
- Run optional quality & plagiarism checks
- Produce front/back covers (ImageMagick or AI-assisted where available)
- Assemble a complete manuscript with title pages, Table of Contents, copyright pages,
	epilogue/appendices/acknowledgements/etc.
- Export the final book in EPUB, PDF and other common ebook formats ready for platforms
	such as Amazon KDP.

### ✨ Key Points
- Designed to use free tools and services where possible. When AI APIs are used, the
	project supports Gemini (recommended), Ollama, Groq and OpenAI as configurable
	providers via environment variables. If you do not set API keys the scripts will
	fall back to purely local tools (ImageMagick, Pandoc, TeX) for compilation and
	simple auto-generated covers.
- Created the final front/back covers and an author picture manually using the free
	ChatGPT web UI (no paid API) to avoid API costs for the cover artwork.
- Conducted a proof-of-concept to test whether a high-quality book could be
	created by AI and pass Amazon Kindle Direct Publishing quality checks. I used this
	toolkit to generate and publish two books which passed KDP checks and are live on
	Amazon. Those books were not marketed — this was an experiment.

### 🗂️ Published Books

- The Playful Path: Unlocking Your Child's Potential Through Joyful, Play-Based Learning for Ages 3-8 — https://a.co/d/hAg2DWe
- The Micro-Influence Advantage: Building Your Niche Brand and Monetizing Your Passion Online — https://a.co/d/3zwHBZJ

### 🎨 Cover Images

Here are the published-book covers:

<p>
	<img src="covers/front/playful-path-cover.png" alt="The Playful Path" width="260" style="margin-right:18px;" />
	<img src="covers/front/micro-influence-cover.png" alt="The Micro-Influence Advantage" width="260" />
</p>

### 🔗 Links

<p>
	<img src="playful-path-images/playful-path-amazon.png" alt="The Playful Path" width="300" style="margin-right:18px;" />
	<img src="micro-influence-images/micro-influence-amazon.png" alt="The Micro-Influence Advantage" width="300" />
</p>

- The Playful Path — https://a.co/d/hAg2DWe
- The Micro-Influence Advantage — https://a.co/d/3zwHBZJ

📌 Status
------
Everything required to generate and compile a book is included as scripts and
helper utilities. Some features require external programs or optional API keys for
best results (Gemini, Ollama, Groq, OpenAI). When not available the workflow still
works for basic generation and compilation using local tools.

🛠️ Quick Overview of Main Scripts
-----------------------------
- `compile_book.sh` — Combine an outline and chapter files into a manuscript and
	export EPUB/PDF/MOBI/AZW3/Markdown/HTML. Lots of options (cover, backcover, author,
	ISBN, publisher, version selection, generate cover, fast mode). See the script
	usage text for full CLI reference.
- `optimized_chapter_handler.sh` — Provide quality checks and chapter length handling. It
	Can extend chapters, review for quality, and rewrite chapters when needed.
- `generate_appendices.sh` — Generate preface, introduction, dedication, acknowledgments,
	epilogue, glossary, discussion guide, further reading, and appendices using an AI
	provider (Gemini recommended). It extracts context from your outline and sample
	chapter to produce well-formatted markdown sections.
- `multi_provider_ai_simple.sh` — Multi-provider helper and `smart_api_call` wrapper.
	It detects available AI providers (Gemini, Groq, Ollama, OpenAI) and cycles/falls
	back as needed. Also includes provider status and quick tests.
- `kdp_market_analyzer.sh`, `topic_market_research.sh`, `market_analyzer.py` and
	other market-research tools — A suite for free-market analysis and KDP opportunity
	scoring (Amazon scraping, trend guidance, keyword/title suggestions). Useful
	for validating topic choices before writing.
- `add_animations.sh` — Helper to add terminal animations to long-running steps.
- `test_extract_chapters.sh` — Small test harness for chapter extraction logic.
- `migrate_book_outputs.sh` — Helps organize loose outline files into structured
	book directories under `book_outputs/`.

⚙️ Prerequisites
-------------
Install the following to get full functionality (macOS / Linux):

- Pandoc (required for EPUB/HTML/PDF pipeline)
- A LaTeX distribution (TeX Live, MacTeX) for best PDF output (pdflatex/xelatex/lualatex)
- ImageMagick (`convert` / `magick`) for cover generation and image resizing
- Jq (JSON parsing helpers used by AI cover generation code)
- Curl
- Python3 + pip packages: requests, beautifulsoup4 (used by market research tools)

On macOS you can quickly install essentials via Homebrew:

```bash
brew install pandoc imagemagick jq
# Install MacTeX (large) or use BasicTeX for smaller footprint:
brew install --cask mactex
pip3 install requests beautifulsoup4
```

🔑 Environment Variables / API Keys
--------------------------------
The scripts support multiple AI providers. Set the corresponding environment
variables to enable them:

- `GEMINI_API_KEY` — (recommended) Use Gemini for text-generation tasks (outlines,
	chapters, appendices, references). The code targets Gemini models and includes
	rate-limit handling.
- `OPENAI_API_KEY` — Optional, used by some cover-generation and provider fallbacks.
- `GROQ_API_KEY` — Optional alternative provider.
- `OLLAMA` — If you run Ollama locally the scripts will try to call it for local
	LLM generations.

If none of the above keys are present the generator will still run but rely on
local tools and the basic ImageMagick cover-generator fallback.

🚀 Typical Workflow (High-level)
-----------------------------
1. Prepare a book outline file in a directory under `book_outputs/` or create a new
	directory for your book. The outline file should be named like `book_outline_*.md`
	(the scripts offer auto-detection of the most recent book if you omit the path).
2. Use the multi-provider helpers and `optimized_chapter_handler.sh` to generate or
	improve chapters. The `generate_chapter_with_smart_api` helpers are in the
	`multi_provider_ai_simple.sh` script and are used by higher-level generation
	workflows.
3. Optionally run `generate_appendices.sh /path/to/book` to auto-create Preface,
	Introduction, Dedication, Acknowledgments, Glossary, Appendices, etc. This
	Requires `GEMINI_API_KEY` set for full automation.
4. Run `./compile_book.sh [book_directory] [output_format] [version] [options]` to
	assemble chapters, generate metadata, include cover/back cover and export
	EPUB/PDF/HTML/Markdown formats.

🧭 Examples — Common Commands
--------------------------
```bash
# Compile the most recent book in all formats (auto detect):
./compile_book.sh

# Compile a specific book directory as EPUB only with a custom author:
./compile_book.sh ./book_outputs/my-book epub --author "Jane Doe"

# Compile a given book as final version, attach a local cover and back cover:
./compile_book.sh ./book_outputs/my-book all 3 --cover "/path/to/cover.png" --backcover "/path/to/back.png" --isbn "978-1-2345-6789-7"

# Generate appendices and extras for a book (requires GEMINI_API_KEY):
./generate_appendices.sh ./book_outputs/my-book

# Run a quick provider status and tests using the multi-provider helper:
./multi_provider_ai_simple.sh status
./multi_provider_ai_simple.sh test

# Run market research for a topic (creates analysis files in research data folder):
./kdp_market_analyzer.sh "digital minimalism"
```

📝 Notes on `compile_book.sh` Options
---------------------------------
- `book_directory` — Path to a book folder (if omitted the script auto-detects the
	Most recent directory under `book_outputs/`).
- `output_format` — One of `all|epub|pdf|html|markdown|mobi|azw3` (default `all`).
- `version` — Manuscript version selector: `1` original, `2` edited, `3` final (default 3).
- `--author`, `--cover`, `--backcover`, `--isbn`, `--publisher`, `--year` — Set
	Metadata used during compilation.
- `--generate-cover` — Ask the script to attempt an AI-generated cover (requires
	`OPENAI_API_KEY` or other image API keys and `jq`), otherwise an ImageMagick fallback
	Will create a simple cover.
- `--fast` — Skip slow conversions (mobi/azw3) and some post-processing.

📦 Output Layout
-------------
When compilation completes an `exports_<TIMESTAMP>/` directory will be created
inside the book directory. It typically includes:

- The generated manuscript markdown file (manuscript_final_*.md)
- Metadata.yaml used for pandoc conversions
- `book.css` for ebook styling
- Generated `*.epub`, `*.pdf`, and other requested formats
- Used images: cover/back-cover/author-photo/publisher logo

🔁 Repro Workflow (Concise)
------------------------
1. Create or generate an outline: `book_outline.md` in `book_outputs/<book>/`.
2. Generate chapter drafts using the chapter handler/smart API calls.
3. Run chapter reviews/quality checks and extend chapters to target lengths.
4. Generate appendices and extras.
5. Create or provide a cover image. If you want to avoid API costs you can use
	Free ChatGPT web UI (manual) to design cover/back/author photos and drop them
	into the script directory as `cover.png`, `back-cover.png`, or pass `--cover`.
6. Run `./compile_book.sh` to export final manuscript files and ebook formats.

💡 Why I Built This (Short Personal Note)
-------------------------------------
I built this project to test whether a high-quality, KDP-acceptable book could be
created end-to-end with AI and free/open tools. The toolkit proved capable: I used
It to create, proof and publish two books on Amazon. This repo collects the
Automation I used and the market research utilities that helped choose topics.
I do not intend to market those books; they were a research project to see what's
possible.

🗂️ Files of Interest (Quick Map)
----------------------------
- `compile_book.sh` — Main compilation pipeline (manuscript -> epub/pdf/html)
- `optimized_chapter_handler.sh` — Extensions, reviews, and quality helpers
- `generate_appendices.sh` — Creates prefatory and back-matter content
- `multi_provider_ai_simple.sh` — Provider selection, smart_api_call, status/test
- `kdp_market_analyzer.sh`, `market_analyzer.py`, `trends_analyzer.py` — Market research
- `add_animations.sh` — Small helper to add terminal animations
- `migrate_book_outputs.sh` — Organize loose outlines into book directories
- `test_extract_chapters.sh` — Test harness for chapter extraction logic
- Assets: `cover.png`, `back-cover.png`, `author-photo.png` (example/placeholder files)

⚖️ Ethics & Legal
--------------
Please ensure that the content you generate and publish follows all legal and
platform rules. AI can accelerate content creation but you are responsible for
copyright, rights clearance, originality, and any platform-specific policies.

🤝 Contributing & Improvements
---------------------------
If you'd like to contribute improvements (tests, tighter formatting for KDP,
better LaTeX templates, or integrations with publishing tools), open an issue or
submit a pull request. Small, focused changes that improve reliability or add
tests are easiest to accept.

📜 License
-------
This repo contains example scripts for demonstration and research purposes. Add
your own license file at the repository root to declare terms if you plan to
publish or share this code widely.

✉️ Contact
-------
If you need clarifications about usage or want to share results from running the
toolkit, feel free to open an issue in this repository or reach out in the project
channels.

Enjoy exploring what automated tools can build — responsibly.

