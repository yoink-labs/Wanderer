# Setting up GitHub Sponsors for yoink-labs

These are the steps a person has to do by hand, in GitHub's and Stripe's
own pages, to turn on GitHub Sponsors for the `yoink-labs` organization.
Nothing here can be done from this repo or by an agent. Harris does them.

Yoink Labs is a venture inside **Undrift LLC**, so the legal entity on the
Stripe account and the tax form is Undrift LLC, not "Yoink Labs".

Based on GitHub's docs as read on 2026-11-17. GitHub changes this flow from
time to time, so check the linked pages if a step looks different.

- [Setting up GitHub Sponsors for your organization](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/setting-up-github-sponsors-for-your-organization)
- [About GitHub Sponsors](https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors)
- [Tax information for GitHub Sponsors](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/tax-information-for-github-sponsors)
- [GitHub Sponsors Additional Terms](https://docs.github.com/en/site-policy/github-terms/github-sponsors-additional-terms)

## Before you start

- **Turn on two-factor authentication for your own GitHub account.** GitHub:
  "Before your organization can become a sponsored organization, you must
  enable 2FA for your account on GitHub." This is the account you'll use for
  the steps below. See
  [Configuring two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication).
- **Use an account that manages the `yoink-labs` org.** The org has to show
  up in your list on the "Get sponsored" page. The docs don't name a role,
  but an org owner is the safe choice.
- **Have Undrift LLC's details ready:** legal name, EIN, business address,
  and a US bank account for payouts. The person setting up must live in the
  same supported region as the bank account. The US is supported. GitHub
  says the account can be a personal or a dedicated business account. Use
  Undrift LLC's business account so the money doesn't go to a person.
- **Get the identity details right the first time.** GitHub warns that
  identity information is "difficult to update" after the application has
  been submitted.

## 1. Apply for the org's Sponsors profile

1. Go to [github.com/sponsors](https://github.com/sponsors) and click
   **Get sponsored**.
2. Next to `yoink-labs`, click **Join the waitlist**. The page assumes the
   org has an invitation, so if the button isn't there, the org may have to
   wait for one.
3. Fill in the contact information. Use a shared Undrift address, such as
   `operations@undrift.dev`, so a business inbox gets the notices rather
   than a personal one.
4. For payouts, choose **bank account**, not a fiscal host. A fiscal host
   can only be picked at signup. Changing that choice later means contacting
   GitHub Support.
5. Read the
   [Additional Terms](https://docs.github.com/en/site-policy/github-terms/github-sponsors-additional-terms)
   and the Privacy Statement, then click **Submit**.

## 2. Connect a Stripe account for payouts

From the org's Sponsors dashboard, open **Stripe Connect account** and
follow the prompts. Stripe asks for the business details:

- Business type: company / LLC, legal name **Undrift LLC**, with its EIN.
- The representative: Harris, as a person with authority at Undrift LLC.
  Stripe asks for personal identity details here.
- Payout bank account: Undrift LLC's US business account.

Payout terms from GitHub's Additional Terms: with Stripe Connect, payouts
arrive on the 22nd of each month for the balance since the last payout,
whatever the amount. The first payout comes 60 days after the first
sponsorship starts. See
[Managing your payouts](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/managing-your-payouts-from-github-sponsors).

## 3. Submit the tax form (W-9)

From the dashboard, go to **Overview** and then **tax forms**. Stripe
collects the form and emails when it's due.

- Undrift LLC is a US taxpayer, so the form is a **W-9** in Undrift LLC's
  name with its EIN. GitHub: "If you are a taxpayer in the United States,
  you must submit a W-9 before you can publish your GitHub Sponsors
  profile."
- The org setup page links the IRS instructions for **W-8BEN-E**. That form
  is for entities outside the US, so it shouldn't apply to Undrift LLC. If
  Stripe asks for it anyway, check with Stripe before filing.
- The right W-9 boxes depend on how Undrift LLC is taxed (single-member
  disregarded entity, partnership or corporation). That's a question for
  whoever does Undrift's taxes.
- At tax time: GitHub sends a 1099-NEC by January 31 to US taxpayers who
  earned more than $600 in the year.
- GitHub can hold payouts until the tax form is in.

## 4. Fill in the profile

In the dashboard's profile section
([Editing your profile details](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/editing-your-profile-details-for-github-sponsors)):

- **Short bio** and **Introduction.** Say what Yoink Labs makes and that the
  apps are free, with no paywall. Don't promise anything to sponsors that
  the roadmap doesn't already show.
- **Meet the team:** up to six org members, each with an optional line.
- **Featured work:** up to six repositories, such as `yoink-labs/Wanderer`.
- Optionally opt in to being featured on github.com/sponsors.

## 5. Create tiers

See [Managing your sponsorship tiers](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/managing-your-sponsorship-tiers).

- Up to 10 monthly tiers and 10 one-time tiers, in US dollars.
- **Once a tier is published, its price can't be changed.** To change a
  price you retire the tier and make a new one. The description and rewards
  can still be edited.
- You can set a minimum for custom amounts. It applies to both monthly and
  one-time sponsorships.
- Keep rewards to thanks and credit. A tier must not unlock anything in an
  app, because Yoink Labs apps have no paywall.

## 6. Request approval

Click **Request approval** on the dashboard. GitHub says "it may take a few
days" to review. When it's approved, the profile goes live on its own at
`https://github.com/sponsors/yoink-labs`.

## 7. After the profile is live

1. In each repo, go to **Settings → General → Features** and tick
   **Sponsorships**. This makes the **Sponsor** button read
   `.github/FUNDING.yml`
   ([Displaying a sponsor button](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository)).
   Wanderer's file already contains `github: [yoink-labs]`.
2. Check that the button on the Wanderer repo opens the org's Sponsors
   page.
3. Update the "Project funding" line in [ROADMAP.md](../ROADMAP.md). Until
   this step, nothing public should say people can sponsor or tip.

## Fees

GitHub charges nothing on sponsorships from personal accounts. Sponsorships
paid by organization accounts carry a fee of up to 6%: 3% for card
processing (waived for invoiced billing) and a 3% service fee
([About GitHub Sponsors](https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors)).

## Still Harris's call

- **Which email** goes on the Sponsors contact and the Stripe account.

`LICENSE` now names Undrift LLC as the copyright holder, the same entity as
the Stripe account and the W-9.
