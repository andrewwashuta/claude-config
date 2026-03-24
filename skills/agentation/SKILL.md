---
name: agentation
description: Install and set up Agentation visual feedback tool for AI coding agents. Detects package manager, installs the npm package, and adds the component to the app.
---

# Agentation Setup

Install and configure [Agentation](https://agentation.dev) — a visual feedback tool that lets you click elements on your page, add notes, and copy structured output that helps AI coding agents find the exact code you're referring to.

## Steps

1. **Detect the package manager** in the current project (look for `bun.lock` → bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` or fallback → npm).

2. **Install the package as a dev dependency**:
   ```bash
   <detected-pm> install agentation -D
   # e.g.: npm install agentation -D
   # e.g.: bun add agentation -d
   ```

3. **Add the `<Agentation />` component** to the app's root layout or entry point — it should render alongside the main app content, NOT wrap it:
   ```tsx
   import { Agentation } from 'agentation';

   // Add AFTER (sibling to) your app content, inside a fragment or wrapper:
   <>
     <YourApp />
     <Agentation />
   </>
   ```

   - For **Next.js**: Add to `app/layout.tsx` inside the `<body>` tag, after `{children}`
   - For **Vite/CRA**: Add to `src/App.tsx` or `src/main.tsx`
   - For **Remix**: Add to `app/root.tsx`
   - Only render in development — wrap in `process.env.NODE_ENV === 'development'` or equivalent

4. **Confirm** the setup by telling the user to run their dev server and look for the Agentation toolbar in the bottom-right corner.

## Key Details

- React 18+ required
- Zero runtime dependencies
- Desktop browsers only
- The toolbar appears in the bottom-right corner — click to activate, then click any element to annotate
- Structured markdown output with CSS selectors, positions, and context is copied to clipboard for pasting to agents
