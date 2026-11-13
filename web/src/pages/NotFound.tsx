import { Link } from "react-router-dom";
import { EmptyState } from "../components/States";

export default function NotFound() {
  return (
    <div className="page-shell page-shell--narrow">
      <EmptyState
        title="This path doesn't exist"
        message="The page may have moved, or the trip link is incomplete."
        action={{ label: "Back to your trips", onClick: () => { window.location.href = "/"; } }}
      />
      <p className="quiet-note">
        Or <Link to="/guides">browse the field guides</Link>.
      </p>
    </div>
  );
}
