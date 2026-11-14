import { useEffect } from "react";
import { BrowserRouter, Route, Routes, useLocation } from "react-router-dom";
import { SessionHost } from "./auth/session";
import { AppHeader } from "./components/AppHeader";
import { ToastProvider } from "./components/Toast";
import { ThemeProvider } from "./lib/theme";
import Explore from "./pages/Explore";
import GuideDetail from "./pages/GuideDetail";
import Home from "./pages/Home";
import Landing from "./pages/Landing";
import SignIn from "./pages/SignIn";
import NotFound from "./pages/NotFound";
import Profile from "./pages/Profile";
import TripWorkspace from "./pages/TripWorkspace";

function ScrollToTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: "instant" });
  }, [pathname]);
  return null;
}

function Shell() {
  return (
    <>
      <ScrollToTop />
      <a href="#main-content" className="skip-link">Skip to content</a>
      <AppHeader />
      <main id="main-content">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/about" element={<Landing />} />
          <Route path="/sign-in" element={<SignIn />} />
          <Route path="/guides" element={<Explore />} />
          <Route path="/guides/:guideId" element={<GuideDetail />} />
          <Route path="/trips/:tripId" element={<TripWorkspace />} />
          <Route path="/trips/:tripId/:tool" element={<TripWorkspace />} />
          <Route path="/profile" element={<Profile />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
    </>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <SessionHost>
        <ToastProvider>
          <BrowserRouter>
            <Shell />
          </BrowserRouter>
        </ToastProvider>
      </SessionHost>
    </ThemeProvider>
  );
}
