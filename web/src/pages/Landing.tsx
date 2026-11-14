import {
  ArrowDown,
  ArrowRight,
  Compass,
  Globe2,
  Heart,
  MapPin,
  Route,
  Smartphone,
} from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { PlanTripDialog } from "../components/PlanTripDialog";

export default function Landing() {
  const [planning, setPlanning] = useState(false);
  return (
    <div className="landing-page">
      <section className="journey-hero" aria-labelledby="journey-title">
        <img
          className="journey-hero__photo"
          src="/images/iceland.jpg"
          alt="A river winding through a lush green canyon in Iceland"
          fetchPriority="high"
        />
        <div className="journey-hero__shade" />
        <div className="journey-hero__content">
          <span className="journey-eyebrow">
            <span /> FOR THE WAY YOU WANDER
          </span>
          <h1 id="journey-title">
            Less planning.
            <br />
            More <em>out there.</em>
          </h1>
          <p>
            The little places. The long way round.
            <br />A home for every part of your next adventure.
          </p>
          <div className="journey-actions">
            <button
              className="button journey-primary"
              onClick={() => setPlanning(true)}
            >
              Plan your next trip <ArrowRight size={18} />
            </button>
            <a className="button journey-secondary" href="#in-your-pocket">
              <Smartphone size={18} /> Meet the iOS app
            </a>
          </div>
          <span className="journey-hero__note">
            Free to explore. No account needed.
          </span>
        </div>
        <div className="hero-phone" aria-label="Wanderer iOS app preview">
          <div className="phone-label">
            <span className="live-dot" /> THE REAL APP. READY TO ROAM.
          </div>
          <Phone
            screen="ios-planner-light"
            alt="The current Wanderer iOS planner showing a Kyoto itinerary and map"
            priority
          />
          <div className="hero-phone__tag">
            <MapPin size={17} />
            <div>
              <strong>A little less lost.</strong>
              <span>A lot more here.</span>
            </div>
          </div>
        </div>
        <div className="journey-hero__bottom">
          <span>
            <MapPin size={14} /> Somewhere along the way, Iceland
          </span>
          <a href="#made-for-the-journey">
            Keep wandering <ArrowDown size={15} />
          </a>
        </div>
      </section>

      <div className="journey-values">
        <span>
          <Compass size={17} /> A plan with room for a detour
        </span>
        <span>
          <Globe2 size={17} /> Web + iOS, together
        </span>
        <span>
          <Heart size={17} /> Open source. No paywall.
        </span>
      </div>

      <section
        className="journey-section destination-section"
        id="made-for-the-journey"
      >
        <div className="journey-section__heading">
          <div>
            <p className="journey-kicker">THE WORLD IS STILL BIG</p>
            <h2>Start with a little wonder.</h2>
          </div>
          <p>
            You bring the curiosity.
            <br />
            We’ll keep the plans together.
          </p>
        </div>
        <div className="destination-grid">
          {[
            ["kyoto", "Kyoto", "Slow mornings. A thousand little discoveries."],
            ["lisbon", "Lisbon", "Follow the light. Take the next tram."],
            [
              "alps",
              "Higher ground",
              "A fresh perspective, a little further up.",
            ],
          ].map(([image, title, copy]) => (
            <button
              className="destination-card"
              key={image}
              onClick={() => setPlanning(true)}
            >
              <img
                src={`/images/${image}.jpg`}
                alt={
                  title === "Higher ground"
                    ? "Dramatic mountain peaks beneath an open sky"
                    : `A view of ${title}`
                }
                loading="lazy"
              />
              <span className="destination-card__arrow">
                <ArrowRight size={19} />
              </span>
              <span className="destination-card__copy">
                <span>YOUR NEXT CHAPTER</span>
                <strong>{title}</strong>
                <small>{copy}</small>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="pocket-section" id="in-your-pocket">
        <div className="pocket-section__phones">
          <Phone
            screen="ios-home-light"
            alt="Wanderer iOS Trips home with the Kyoto demo trip"
          />
          <Phone
            screen="ios-planner-dark"
            alt="Wanderer iOS planner in dark appearance"
          />
        </div>
        <div className="pocket-section__copy">
          <p className="journey-kicker">BIG ADVENTURES. POCKET-SIZED.</p>
          <h2>
            Your whole trip.
            <br />
            Right here.
          </h2>
          <p>
            A day-by-day itinerary, the places you can’t miss, and a map that
            brings it all together. Plan on the big screen. Take Wanderer along
            for the ride.
          </p>
          <div className="pocket-features">
            <span>
              <Route size={20} /> Every day, your way
            </span>
            <span>
              <MapPin size={20} /> The route comes together
            </span>
            <span>
              <Heart size={20} /> Shared plans. Your own detours.
            </span>
          </div>
          <div className="journey-actions">
            <button
              className="button button--primary button--large"
              onClick={() => setPlanning(true)}
            >
              Start on the web <ArrowRight size={17} />
            </button>
            <a
              className="text-link"
              href="https://github.com/yoink-labs/Wanderer"
              target="_blank"
              rel="noreferrer"
            >
              Follow the iOS beta <ArrowRight size={15} />
            </a>
          </div>
          <small className="beta-note">
            Made for iPhone. Currently in TestFlight beta.
          </small>
        </div>
      </section>

      <section className="journey-outro">
        <img
          src="/images/bali.jpg"
          alt="Lush green landscape and water in Bali"
          loading="lazy"
        />
        <div>
          <p className="journey-eyebrow">GO SOMEWHERE THAT STAYS WITH YOU</p>
          <h2>
            The best part
            <br />
            is still out there.
          </h2>
          <div className="journey-actions">
            <button
              className="button journey-primary"
              onClick={() => setPlanning(true)}
            >
              Let’s make a plan <ArrowRight size={18} />
            </button>
            <Link className="button journey-secondary" to="/guides">
              Find some inspiration
            </Link>
          </div>
        </div>
      </section>
      <footer className="journey-footer">
        <div>
          <strong>Wanderer</strong>
          <p>Made for the journey, by Yoink Labs.</p>
        </div>
        <p>
          Open source. Free to use.
          <br />
          An optional tip jar in the iOS app. Never a paywall.
        </p>
        <div>
          <a
            href="https://github.com/yoink-labs/Wanderer"
            target="_blank"
            rel="noreferrer"
          >
            Explore the source <ArrowRight size={14} />
          </a>
          <Link to="/sign-in">
            Sign in to Wanderer <ArrowRight size={14} />
          </Link>
          <a href="/images/CREDITS.md">Photography credits</a>
        </div>
      </footer>
      <PlanTripDialog open={planning} onClose={() => setPlanning(false)} />
    </div>
  );
}

export function Phone({
  screen,
  alt,
  priority = false,
}: {
  screen: string;
  alt: string;
  priority?: boolean;
}) {
  return (
    <div className="device-frame">
      <img
        src={`/images/app/${screen}.webp`}
        alt={alt}
        width={604}
        height={1312}
        loading={priority ? "eager" : "lazy"}
      />
      <span className="device-frame__island" aria-hidden="true" />
    </div>
  );
}
