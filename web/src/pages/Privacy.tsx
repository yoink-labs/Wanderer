import { useEffect } from "react";
import {
  PRIVACY_INTRO,
  PRIVACY_SECTIONS,
  PRIVACY_TITLE,
  PRIVACY_UPDATED,
  privacySegments,
} from "../content/privacy";

function Inline({ text }: { text: string }) {
  return (
    <>
      {privacySegments(text).map((segment, index) =>
        segment.href ? (
          <a
            key={index}
            href={segment.href}
            {...(segment.href.startsWith("http") ? { target: "_blank", rel: "noreferrer" } : {})}
          >
            {segment.text}
          </a>
        ) : (
          <span key={index}>{segment.text}</span>
        ),
      )}
    </>
  );
}

export default function Privacy() {
  useEffect(() => {
    const previous = document.title;
    document.title = "Privacy policy · Wanderer";
    return () => {
      document.title = previous;
    };
  }, []);

  return (
    <article className="legal-page page-shell page-shell--narrow">
      <header className="legal-page__header">
        <span className="legal-page__eyebrow">Wanderer</span>
        <h1>{PRIVACY_TITLE}</h1>
        <p className="legal-page__updated">Last updated {PRIVACY_UPDATED}</p>
        {PRIVACY_INTRO.map((paragraph) => (
          <p key={paragraph} className="legal-page__lede">
            <Inline text={paragraph} />
          </p>
        ))}
      </header>
      {PRIVACY_SECTIONS.map((section) => (
        <section key={section.id} id={section.id} aria-labelledby={`${section.id}-title`}>
          <h2 id={`${section.id}-title`}>{section.title}</h2>
          {section.blocks.map((block, index) =>
            "p" in block ? (
              <p key={index}>
                {block.lead && <strong>{block.lead} </strong>}
                <Inline text={block.p} />
              </p>
            ) : (
              <ul key={index}>
                {block.list.map((item) => (
                  <li key={item}>
                    <Inline text={item} />
                  </li>
                ))}
              </ul>
            ),
          )}
        </section>
      ))}
    </article>
  );
}
