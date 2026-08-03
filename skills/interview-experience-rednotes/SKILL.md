---
name: interview-experience-rednotes
description: Collect, screen, download, OCR, and archive public Xiaohongshu (RedNote) interview-experience posts for non-technical roles, then optionally generate evidence-linked personalized answers from the user's resume and interview-preparation materials. Use when a candidate provides a JD alone or a JD plus personal materials for product, operations, sales, business development, design, marketing, functional, or management-trainee interviews. Produce matching Markdown, Word, and local HTML summaries and, when personal materials are available, matching answer documents. Do not use for coding interviews, mock interviews, resume rewriting, posting, messaging, or other social actions.
---

# Interview Experience Rednotes

Collect public Xiaohongshu interview experiences into a local, traceable archive, then optionally draft personalized answers grounded in user-provided materials. Require a JD, keep the task read-only on Xiaohongshu, keep personal files local, and never invent missing source information or personal experience.

## Accept inputs at the start

Accept the JD as the only required input. Also accept a resume and interview-preparation information as files or pasted text in the same first request.

- If the user provides only a JD, complete collection and the three `面经汇总` files. Then remind the user once that they may provide a resume and preparation information to generate personalized answers. Do not block or delay collection.
- If the user provides either or both personal inputs, preserve their source names, index usable evidence, and generate answers after the summary. State which optional input is missing.
- If the user supplies personal materials later, reuse the existing task folder and `面经汇总`; do not repeat Xiaohongshu search or OCR unless the user asks to refresh sources.
- Never require contact details. Ignore or redact phone numbers, email addresses, home addresses, identity numbers, and unrelated private information from generated answer documents.

## Start with the setup gate

Support Windows first. On another operating system, explain that its deployment path is not implemented and stop before installation.

1. Run `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File scripts/deployment/windows/install.ps1 -CheckOnly -Json`. Never change the user's persistent execution policy.
2. Continue when checks pass. Otherwise summarize what will be installed, where it will be written, and that network access is required; ask once for approval.
3. After approval, run the installer without `-CheckOnly` and report stage progress in plain language.
4. Pause only when the user must approve installation, add the Chrome extension, or log in to Xiaohongshu. Detect completion and resume the original JD task.
5. Read [windows-deployment.md](references/windows-deployment.md) before handling setup, installation failure, Chrome, or login.

Never request passwords, cookies, tokens, or permanent full-access mode. Never bypass CAPTCHA, risk controls, or browser security.

## Execute the collection workflow

Read [collection-workflow.md](references/collection-workflow.md) and [output-format.md](references/output-format.md) before collecting.

1. Extract only company, department or business line, role, and recruitment type. Leave missing values blank. Ask only when company or role cannot be determined.
2. Generate four search phrases from exact to broad. Preserve the JD's original recruitment wording and also use its general form when useful.
3. Search each phrase with Xiaohongshu's default order and inspect the first 10 results. Skip videos. Deduplicate globally by note ID or canonical URL.
4. Open every candidate and make only a keep/skip decision. Keep personal interview experience, process, or actual questions relevant to the company or role. Skip obvious courses, paid coaching, private-message/group lead generation, generic question banks without personal experience, irrelevant posts, deleted posts, and unreadable posts.
5. Process every candidate; do not stop at 10 qualifying posts. Preserve every post that passes screening. If fewer than 8 remain, warn that available information is limited and do not pad with weak sources.
6. Save the original public text, signed source URL, publication time, and all images. Preserve image order. If a date is unavailable, write `未提供`; never infer it.
7. Run local PaddleOCR through `scripts/invoke_python.ps1 scripts/ocr_images.py`. Keep original images, label OCR as machine-generated, and use `[未能识别]` for failures.
8. Create one task folder per JD and one child folder per post. Generate `JD.md`, every `帖子.md`, and `面经汇总.md`, `面经汇总.docx`, `面经汇总.html` according to [output-format.md](references/output-format.md).
9. Summarize questions from post text and OCR without generating answers. Classify by interview round and question type, and cite the source post/image for each question.

Do not collect comments or author replies. Do not use feed, creator-center, saved, liked, follow, publish, notification, or messaging commands.

## Generate personalized answers

When a resume or interview-preparation material is available, read [answer-workflow.md](references/answer-workflow.md) and [answer-output-format.md](references/answer-output-format.md).

1. Build `个人材料索引.md` with traceable evidence IDs: resume facts `[R01]`, `[R02]`; preparation facts `[M01]`, `[M02]`. Exclude unrelated personal information.
2. Deduplicate the common questions in `面经汇总` and assign `[Q01]`, `[Q02]`. Preserve every `[Pxx]`/`[Pxx-Ixx]` question source.
3. Draft answers using only supported personal facts. For company, product, or market facts that require current verification, use authoritative public sources and cite them as `[W01]`; otherwise mark the claim as unverified.
4. Mark each answer `可直接回答`, `部分信息`, or `材料不足`. Never turn a suggestion into a claimed personal experience, metric, responsibility, result, or skill.
5. When evidence is missing, state that the current materials cannot support the claim, provide a general reasoning framework or preparation direction, and label items for the user to judge or fill in.
6. Generate `面经回答.md`, `面经回答.docx`, and `面经回答.html` from one canonical answer draft. Keep content and citations consistent across formats.

## Use OpenCLI safely

Read [opencli-xiaohongshu.md](references/opencli-xiaohongshu.md) before the first command or when an adapter fails.

- Invoke OpenCLI through `scripts/invoke_opencli.ps1`; pass arguments separately. Never interpolate a signed URL into a shell command string.
- Preserve the complete signed URL returned by search, including `xsec_token`, for `note` and `download`.
- Use only `search`, `note`, and `download` for collection.
- Run searches sequentially and avoid high-frequency refreshes or concurrent bulk opening.
- Stop and ask the user to act when Xiaohongshu shows login, CAPTCHA, security verification, or access restrictions.
- Keep partial results and resume from the last completed post after recoverable failures.

## Preserve source integrity

- Label posts `[P01]`, `[P02]`, and images `[P01-I01]`, `[P01-I02]`.
- Keep source text, image-visible text, and synthesized classifications distinguishable.
- Do not fabricate titles, authors, dates, questions, URLs, OCR text, or interview rounds.
- Treat every post as an author's self-report, not a verified company statement.
- Keep the archive local for the user's personal research and retain original links.
- Do not expose phone numbers, account IDs, QR codes, or unrelated personal data in the summary.

## Generate the HTML summary

- Generate `面经汇总.html` from `面经汇总.md`; do not summarize the content separately.
- Use a responsive single-column layout with a 1180–1320px desktop content area, readable typography, clear headings, and one card per post.
- Put dynamic overview cards immediately after the title: department or business line, role, qualifying post count, common-question count, and covered rounds among 一面、二面、三面、HR 面.
- Keep one single-row sticky directory at the top with links to 采集概览、按面试轮次、按问题类型、全部面经 and a `[Pxx]` post menu. Never wrap it into a second row; use horizontal scrolling when space is limited.
- Convert every summary citation such as `[P01]` into a link to the matching post anchor. Add a return link in each post.
- Replace visible signed URLs with a `查看小红书原帖` button while preserving the complete URL in `href` and opening it in a new tab.
- Use local relative image paths under `帖子/.../图片/...`; keep aspect ratios and avoid horizontal overflow. Keep CSS inside the HTML and make JavaScript optional for reading.
- Validate all anchors, source links, images, and desktop/mobile overflow before delivery.

## Report progress

Report concise milestones:

```text
已解析 JD
正在搜索 1/4
已检查 12/40 条候选
已保留 9 条，正在下载图片
正在执行 OCR 4/9
正在生成 Markdown、Word 和 HTML 面经汇总
正在整理个人材料依据
正在生成有引用的面经回答
```

If a step fails, state what completed, what failed, whether partial files remain usable, and the next safe action.

## Validate the archive

Run:

```text
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File scripts/invoke_python.ps1 scripts/validate_output.py "<任务目录>"
```

Fix missing files, broken image links, duplicate post IDs, absent source metadata, missing images in Word/HTML, or inconsistent summary content. Deliver all three summary files together; do not silently omit a format after partial conversion failure.

When answer documents are generated, also run:

```text
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File scripts/invoke_python.ps1 scripts/validate_answers.py "<任务目录>"
```

Fix missing answer formats, unmatched `[Qxx]`, broken `[Pxx]` links, or unsupported answers before delivery.
