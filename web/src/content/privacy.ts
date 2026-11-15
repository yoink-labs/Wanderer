/**
 * Wanderer's privacy policy, as data.
 *
 * Both the React page (src/pages/Privacy.tsx) and the static prerender that
 * vite.config.ts writes to dist/privacy.html render from this one source, so
 * a cold load, a crawler and the in-app route all show the same words.
 *
 * Every statement here describes what the code in this repository does
 * (worker/, web/, Wanderer/). Change the policy when that behaviour changes.
 *
 * Inline links use [label](href).
 */

export type PrivacyBlock = { p: string; lead?: string } | { list: string[] };

export interface PrivacySection {
  id: string;
  title: string;
  blocks: PrivacyBlock[];
}

export const PRIVACY_CONTACT = "harris@undrift.dev";
export const PRIVACY_UPDATED = "November 15, 2026";

export const PRIVACY_TITLE = "Privacy policy";

export const PRIVACY_INTRO = [
  "Wanderer is a free, open-source trip planner for iPhone, iPad and the web, made by Yoink Labs. This policy explains what Wanderer collects, where it is kept, who else handles it and how to delete it. It covers the Wanderer iOS app, this website (wanderer.yoinklabs.dev) and the Wanderer API (api.yoinklabs.dev).",
  "The code is public on [GitHub](https://github.com/yoink-labs/Wanderer), so you can check every statement below.",
];

export const PRIVACY_SECTIONS: PrivacySection[] = [
  {
    id: "short-version",
    title: "The short version",
    blocks: [
      {
        list: [
          "No ads, no tracking, and no analytics or crash-reporting tools in the app or on this site. We don't sell or rent your data.",
          "You can plan trips without an account. Guest trips stay on your device or in your browser.",
          "With an account, your trips are stored on Cloudflare so you and the people you invite can see them on any device.",
          "Tips in the iOS app are optional and handled entirely by Apple.",
          "You can delete your account, and everything you own in Wanderer, at any time.",
        ],
      },
    ],
  },
  {
    id: "what-we-collect",
    title: "What we collect",
    blocks: [
      {
        lead: "Your account.",
        p: "Sign-in is handled by Clerk. You can sign in with Apple, with Google, or with your email address and a one-time code (creating an email account also asks for a password, which Clerk stores, not Wanderer). Wanderer receives your Clerk user ID and email address and keeps them with your profile, along with your display name, a profile photo if you upload one, and your language, currency and unit preferences.",
      },
      {
        lead: "Your trips.",
        p: "Everything you add to a trip you create or join: its title, destination, dates and days; places (names, addresses, map coordinates, notes, websites, phone numbers and times); bookings, including confirmation codes, times, locations, costs and notes; expenses, how they are split and settlements; checklists; private stops and bookings that only you can see; and places you mark as visited (country, city and year).",
      },
      {
        lead: "Files and photos.",
        p: "Attachments you add to a trip, such as tickets or confirmations, trip cover images, and your profile photo.",
      },
      {
        lead: "Invites.",
        p: "The email address of anyone you invite to a trip.",
      },
      {
        lead: "Technical data.",
        p: "Wanderer runs on Cloudflare, which processes request details such as IP addresses to deliver and protect the service, and we keep short-lived server logs for fixing problems. Public share pages are rate-limited using a short one-way hash of the visitor's IP address, never the address itself. To avoid applying the same change twice when the app retries a request, the server keeps a record of recent requests for about a day.",
      },
      {
        lead: "What we don't collect.",
        p: "The app never asks for your location, contacts or photo library as a whole (you choose individual photos or files to upload). Wanderer has no advertising identifiers, analytics or crash-reporting tools.",
      },
    ],
  },
  {
    id: "where-it-lives",
    title: "Where your data is stored and who can see it",
    blocks: [
      {
        p: "Account and trip data is stored in a Cloudflare D1 database, and files in Cloudflare R2 storage.",
      },
      {
        list: [
          "People you invite to a trip can see and edit that trip, except for your private stops and bookings.",
          "If you share a trip's link, anyone with it sees a read-only page with the trip's title, destination, dates and each day's stops. It never shows people's names or emails, notes, costs, bookings or files. Making a new link turns the old one off.",
          "Trip cover images and profile photos are served from public web addresses that are hard to guess. Attachments are only reachable through links that expire.",
        ],
      },
    ],
  },
  {
    id: "services",
    title: "Services that handle your data",
    blocks: [
      {
        p: "Wanderer uses these providers to work. Each receives only what is listed.",
      },
      {
        list: [
          "Clerk: sign-in and your sign-in account.",
          "Cloudflare: hosting, the database and file storage for everything above.",
          "Resend: sends trip invite emails. It receives the invitee's email address, the trip's title, the inviter's email address and the invite link.",
          "AeroDataBox (through RapidAPI): live flight status. Our server sends only a flight number and date, never who is asking. Results are cached and shared by everyone tracking the same flight.",
          "Apple: Sign in with Apple, Apple Maps for maps and place search in the iOS app, and App Store payments for tips.",
          "Google: Sign in with Google if you choose it. Directions links open Google Maps only when you tap them.",
          "OpenStreetMap: map tiles and place search (Nominatim) on this website. Your browser requests them directly, so OpenStreetMap receives your IP address and the text you search for.",
          "Open-Meteo: current weather for a trip's destination in the iOS app. The app sends the destination's coordinates, not your location.",
          "Frankfurter: currency exchange rates. The app sends currency codes only.",
          "Unsplash: some suggested trip cover photos load from Unsplash's image servers.",
        ],
      },
    ],
  },
  {
    id: "tips",
    title: "Tips",
    blocks: [
      {
        p: "Tips in the iOS app are optional in-app purchases processed by Apple through the App Store. Wanderer never sees your payment details, and the app doesn't send tip information to our servers. Tipping doesn't unlock anything; every feature is free.",
      },
    ],
  },
  {
    id: "on-your-device",
    title: "On your device",
    blocks: [
      {
        list: [
          "Guest trips are kept on your iPhone or iPad, or in your browser's local storage on the web, until you sign in and choose to save them to your account.",
          "A copy of trips you open is cached on your device or in your browser so you can read them offline.",
          "Flight alerts are local notifications created on your iPhone. The app asks for notification permission first, and you can turn alerts off in Profile.",
        ],
      },
    ],
  },
  {
    id: "deleting",
    title: "Keeping and deleting your data",
    blocks: [
      {
        p: "We keep your data while you have an account.",
      },
      {
        list: [
          "Delete your account in the iOS app under Profile → Delete account. This deletes your Wanderer profile, every trip you own with its places, bookings, expenses and files, your membership of other people's trips, your private items and your visited places. Things you added to someone else's trip stay in that trip without your name attached.",
          "Your sign-in account at Clerk is shared with other Yoink Labs apps and isn't removed by this. Email us to have it deleted too.",
          "Deleting a single trip removes it from Wanderer straight away. Files that were attached to it are removed when you delete your account, or sooner if you ask.",
          "The website doesn't have a delete-account button yet. Email us from your account's email address and we'll delete your account and data.",
          "To remove guest trips and offline copies, delete the app, or clear this site's data in your browser.",
        ],
      },
      {
        p: `To have anything else removed, including your profile photo, email [${PRIVACY_CONTACT}](mailto:${PRIVACY_CONTACT}).`,
      },
    ],
  },
  {
    id: "changes",
    title: "Changes",
    blocks: [
      {
        p: "If this policy changes, we'll update this page and the date at the top.",
      },
    ],
  },
  {
    id: "contact",
    title: "Contact",
    blocks: [
      {
        p: `Questions or requests about your data: [${PRIVACY_CONTACT}](mailto:${PRIVACY_CONTACT}).`,
      },
    ],
  },
];

/** Splits text into plain runs and [label](href) links. */
export function privacySegments(text: string): Array<{ text: string; href?: string }> {
  const out: Array<{ text: string; href?: string }> = [];
  const pattern = /\[([^\]]+)\]\(([^)]+)\)/g;
  let last = 0;
  for (const match of text.matchAll(pattern)) {
    const index = match.index ?? 0;
    if (index > last) out.push({ text: text.slice(last, index) });
    out.push({ text: match[1], href: match[2] });
    last = index + match[0].length;
  }
  if (last < text.length) out.push({ text: text.slice(last) });
  return out;
}

const escapeHtml = (value: string) =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

function inlineHtml(text: string): string {
  return privacySegments(text)
    .map((segment) =>
      segment.href
        ? `<a href="${escapeHtml(segment.href)}">${escapeHtml(segment.text)}</a>`
        : escapeHtml(segment.text),
    )
    .join("");
}

/** Static markup for the prerendered page; mirrors <PrivacyArticle />. */
export function privacyArticleHtml(): string {
  const sections = PRIVACY_SECTIONS.map((section) => {
    const blocks = section.blocks
      .map((block) =>
        "p" in block
          ? `<p>${block.lead ? `<strong>${escapeHtml(block.lead)}</strong> ` : ""}${inlineHtml(block.p)}</p>`
          : `<ul>${block.list.map((item) => `<li>${inlineHtml(item)}</li>`).join("")}</ul>`,
      )
      .join("");
    return `<section id="${section.id}" aria-labelledby="${section.id}-title"><h2 id="${section.id}-title">${escapeHtml(section.title)}</h2>${blocks}</section>`;
  }).join("");
  return [
    `<article class="legal-page page-shell page-shell--narrow">`,
    `<header class="legal-page__header">`,
    `<span class="legal-page__eyebrow">Wanderer</span>`,
    `<h1>${escapeHtml(PRIVACY_TITLE)}</h1>`,
    `<p class="legal-page__updated">Last updated ${escapeHtml(PRIVACY_UPDATED)}</p>`,
    PRIVACY_INTRO.map((paragraph) => `<p class="legal-page__lede">${inlineHtml(paragraph)}</p>`).join(""),
    `</header>`,
    sections,
    `</article>`,
  ].join("");
}
