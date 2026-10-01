# Detection of Offensive Messages in Social Media to Protect Online Safety

A full-stack system that detects offensive and harmful messages on social
media platforms, flags them by severity, and gives human moderators a queue
to review. Built as a final-year capstone project.

> **Problem.** Manual moderation does not scale to the volume of content
> posted on social platforms, yet unchecked harassment, hate speech and
> threats cause real harm. This project demonstrates an end-to-end pipeline
> that automatically screens messages, ranks them by how confident the model
> is that they are offensive, and surfaces the riskiest ones to moderators
> first — keeping a human in the loop for the final decision.

---

## Table of contents

1. [What it does](#what-it-does)
2. [Architecture](#architecture)
3. [The machine-learning model](#the-machine-learning-model)
4. [Tech stack](#tech-stack)
5. [Repository layout](#repository-layout)
6. [Quick start](#quick-start)
7. [Manual setup](#manual-setup)
8. [Using the system](#using-the-system)
9. [API overview](#api-overview)
10. [Testing](#testing)
11. [Evaluation results](#evaluation-results)
12. [Design decisions & defense notes](#design-decisions--defense-notes)
13. [Limitations & future work](#limitations--future-work)

---

## What it does

- Accepts a message (text + author + platform) through a web dashboard or REST API.
- Sends the text to a machine-learning service that returns a label
  (`offensive` / `normal`), a probability, and a severity (`low` / `medium` / `high`).
- Stores every analysed message in a database with its verdict.
- Flags offensive messages and places them in a **moderator queue** sorted by severity.
- Lets users **report** messages and lets moderators **resolve** those reports.
- Exposes live statistics (total analysed, flagged rate, breakdown by severity).
- Ships with a conversational assistant endpoint that answers questions like
  *"show stats"*, *"how does it work"*, or *"analyze &lt;some text&gt;"*.

## Architecture

The system is split into three independent services so that the
language-model work (Python) is decoupled from the business/orchestration
layer (Java), which is a common real-world pattern.

```
            ┌─────────────────┐
            │   Dashboard     │   HTML + JS (single page)
            │  (browser UI)   │
            └────────┬────────┘
                     │  REST / JSON
                     ▼
            ┌─────────────────┐        ┌──────────────────┐
            │  Java backend   │  REST  │  Python ML       │
            │  Spring Boot    │───────▶│  service (Flask) │
            │  port 8080      │◀───────│  port 5001       │
            └────────┬────────┘  JSON  └────────┬─────────┘
                     │                          │
                     ▼                          ▼
            ┌─────────────────┐        ┌──────────────────┐
            │    MongoDB      │        │  TF-IDF + linear │
            │ messages,reports│        │  classifier .pkl │
            └─────────────────┘        └──────────────────┘
```

**Why two backends?** The Java service owns persistence, validation,
moderation workflow and the public API. The Python service owns only the
model. This keeps the ML swappable (you could replace the scikit-learn model
with a transformer without touching the Java code) and lets each part be
scaled or tested on its own. If the ML service is ever unreachable, the Java
side falls back to a simple rule-based check so the system degrades instead
of failing.

A full request walk-through is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## The machine-learning model

The detector is a text-classification pipeline:

```
raw text → clean (lowercase, strip URLs/mentions, keep letters)
         → tokenise + remove stop-words + Porter stemming
         → TF-IDF features (word unigrams + bigrams)
         → linear classifier (Logistic Regression vs Linear SVM)
         → probability of "offensive"
         → threshold + severity banding
```

Two models are trained and the one with the better held-out macro-F1 is
saved automatically (see [`trainer.py`](python-ml-service/model/trainer.py)).

**The model leads the decision, not a keyword list.** A small offensive-word
lexicon exists, but it is only used as a transparent secondary signal that
can tip *borderline* cases; it never overrides a confident "normal"
prediction. This is what stops the classic keyword-filter failure where
*"I hate Mondays"* or *"this traffic is killing me"* get wrongly flagged —
both are correctly classified as normal by this system even though they
contain trigger words. That contrast is the clearest evidence that this is a
real classifier and not a blocklist.

Full evaluation numbers are written to
[`python-ml-service/model/metrics.json`](python-ml-service/model/metrics.json)
each time the model is trained, and summarised in
[Evaluation results](#evaluation-results).

## Tech stack

| Layer        | Technology                                            |
|--------------|-------------------------------------------------------|
| Frontend     | HTML, CSS, vanilla JavaScript (single-page dashboard) |
| Backend API  | Java 17, Spring Boot 3 (Web, WebFlux, Validation)     |
| ML service   | Python 3, Flask, scikit-learn, NLTK                   |
| Database     | MongoDB                                               |
| Build / test | Maven, JUnit 5, Mockito, pytest                       |

## Repository layout

```
.
├── README.md                  ← you are here
├── start.sh / stop.sh         ← one-command run / stop scripts
├── demo.py                    ← scripted live demo against the running API
├── dashboard.html             ← web UI
├── docs/
│   ├── API_REFERENCE.md       ← every endpoint, with examples
│   └── ARCHITECTURE.md        ← request flow, component responsibilities
├── java-backend/              ← Spring Boot service (port 8080)
│   └── src/main/java/com/oms/
│       ├── controller/        ← REST endpoints
│       ├── service/           ← business logic + ML client
│       ├── repository/        ← MongoDB data access
│       ├── model/ dto/        ← entities and request/response objects
│       ├── config/            ← WebClient configuration
│       └── exception/         ← centralised error handling
└── python-ml-service/         ← Flask + scikit-learn service (port 5001)
    ├── app.py                 ← REST API (analyze, batch, bias-probe, stats)
    ├── preprocessor.py        ← text cleaning + lexicon
    ├── test_ml_service.py     ← pytest suite
    ├── data/
    │   └── davidson_labeled.csv  ← cached benchmark dataset (binary labels)
    └── model/
        ├── dataset.py         ← loads benchmark (+seed), with offline fallback
        ├── trainer.py         ← train, compare vs baseline, evaluate, persist
        ├── predictor.py       ← inference (threshold-aware) + explanations
        ├── explainer.py       ← per-word "why flagged" contributions
        ├── classifier.pkl     ← saved model (regenerated on first run)
        └── metrics.json       ← evaluation report
```

## Quick start

Requirements: **Java 17+**, **Python 3.9+**, and (optionally) **MongoDB**.
The system runs without MongoDB — it simply won't persist history in that case.

```bash
bash start.sh      # builds + launches MongoDB, ML service, and Java backend
# ... open dashboard.html in your browser ...
bash stop.sh       # stops everything
```

> `start.sh` expects JDK/Maven/Mongo at the paths set near the top of the
> script. If yours differ, edit those four variables, or follow the manual
> setup below.

## Manual setup

**1. Python ML service**

```bash
cd python-ml-service
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m model.trainer          # trains + saves classifier.pkl and metrics.json
python app.py                    # serves on http://localhost:5001
```

**2. Java backend** (new terminal)

```bash
cd java-backend
./mvnw spring-boot:run            # serves on http://localhost:8080
```

**3. Dashboard** — open `dashboard.html` in a browser.

**4. Optional scripted demo** (with both services running):

```bash
pip install requests
python demo.py
```

## Using the system

- **Analyse a message** — type text in the dashboard input, pick a platform,
  and submit. The verdict and severity appear immediately.
- **Moderator queue** — flagged messages are listed by severity; mark them
  reviewed with an optional note.
- **Assistant** — ask the chat box things like `show stats`,
  `how does it work`, or `analyze you are worthless`.

## API overview

See [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md) for the complete list.
The two most important endpoints:

```http
POST /api/messages/analyze        (Java, 8080)   → analyse + store a message
POST /api/ml/analyze              (Python, 5001) → analyse text only
```

## Testing

```bash
# Python
cd python-ml-service && python -m pytest -v

# Java
cd java-backend && ./mvnw test
```

The Python suite specifically asserts that hard negatives
(*"I hate Mondays"*, *"I could kill for a coffee"*) are **not** flagged, and
that clear insults and threats **are** — the behaviour most likely to be
questioned in a defense.

## Evaluation results

The model is trained and evaluated on the **Davidson et al. (2017)
hate-speech and offensive-language corpus** (~24,800 labelled tweets),
augmented with a small curated seed set so it also handles clean-worded
insults, threats and hard negatives that the tweet corpus under-represents.
The original 3-class labels (hate / offensive / neither) are mapped to a
binary offensive-vs-normal task.

On a stratified 20% held-out test set (~5,000 messages):

| Model               | Accuracy | Macro-F1 |
|---------------------|----------|----------|
| Majority baseline   | ~0.83    | ~0.45    |
| Logistic Regression | ~0.95    | ~0.91    |
| Linear SVM          | ~0.95    | ~0.91    |

The exact, reproducible numbers (plus per-class precision/recall and the
confusion matrix) are written to
[`python-ml-service/model/metrics.json`](python-ml-service/model/metrics.json)
on every training run.

**Why the baseline matters.** The data is ~83% offensive, so a model that
blindly predicts "offensive" reaches ~0.83 accuracy while being useless.
That is exactly why this project reports **macro-F1**, not accuracy: the
baseline's macro-F1 collapses to ~0.45, and the real models nearly double it.
This is the clearest single point to make in the defense about evaluating on
imbalanced data.

> Citation: Davidson, T., Warmsley, D., Macy, M., & Weber, I. (2017).
> *Automated Hate Speech Detection and the Problem of Offensive Language.*
> Proceedings of ICWSM.

## Interactive features for the demo

Three features were added specifically to make the system explainable and
defensible rather than a black box:

1. **Per-word explanations ("why flagged").** For every flagged message the
   model surfaces the tokens that drove the decision, with relative weights
   (e.g. *worthless*, *stupid*, *idiot*). Implemented in
   [`model/explainer.py`](python-ml-service/model/explainer.py) using the
   linear model's coefficients × TF-IDF weights — no heavy libraries. Shown
   as chips under each message in the dashboard.

2. **Adjustable decision threshold.** A slider on the dashboard changes the
   probability cut-off in real time, letting you watch the
   **precision/recall trade-off** live — lower threshold catches more
   (higher recall, more false alarms); higher threshold is stricter. This
   reframes moderation as a tunable policy decision, not a fixed binary.

3. **Bias / fairness probe.** A one-click panel runs a fixed set of phrases —
   some genuinely abusive, some merely informal (*"that party was crazy"*,
   *"damn good game"*) — to expose where the model over- or under-reacts.
   This makes the fairness discussion concrete instead of hand-waved, and
   honestly surfaces a real limitation (informal/profane-but-harmless
   language can be over-flagged because of how the tweet corpus is labelled).

## Design decisions & defense notes

- **Microservice split (Java + Python).** Lets the ML evolve independently
  and demonstrates service-to-service communication; the Java fallback means
  one service failing doesn't take down the system.
- **Model-led decision with a transparent lexicon assist.** Avoids the
  false-positive problem of pure keyword filters while still giving
  moderators an explainable signal (`pattern_flag`).
- **Severity banding** turns a raw probability into an actionable triage
  level, so moderators see the most dangerous content first.
- **Human-in-the-loop.** The system flags and ranks; it never silently
  deletes. A moderator makes the final call, which is the responsible design
  for content moderation.
- **Graceful degradation.** No MongoDB → predictions still work; no ML
  service → rule-based fallback. The demo never hard-crashes.

## Limitations & future work

- The model is trained on the Davidson Twitter corpus plus a curated seed
  set. It inherits that corpus's biases: informal or profane-but-harmless
  language can be over-flagged, and the data skews toward US English tweets.
  The built-in **bias probe** demonstrates this directly.
- The model is English-only and context-limited; sarcasm, coded language and
  multilingual abuse are known hard cases.
- Like all moderation models it can carry **bias** (e.g. over-flagging
  reclaimed slurs or certain dialects). A production deployment would need a
  fairness audit across demographic groups before going live.
- Natural extensions: a transformer model (e.g. DistilBERT/HateBERT),
  per-platform thresholds, an appeals workflow, and authentication for the
  moderator dashboard.

---

*Built for educational purposes. Content-moderation models should be
fairness-audited and kept human-in-the-loop before any real deployment.*
