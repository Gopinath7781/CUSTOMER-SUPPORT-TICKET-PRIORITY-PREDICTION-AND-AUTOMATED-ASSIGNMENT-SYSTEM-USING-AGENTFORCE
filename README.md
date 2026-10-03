# Customer Support Ticket Priority Prediction (Salesforce + Agentforce)

## Contents
- `force-app/`  object, 10 fields, layout, permission set, auto-launched flow
- `scripts/`    seed.apex (sample data), test_flow.apex (flow test)
- `deploy.bat`  Windows: deploy + permission set (+ sample data with --seed)
- `setup_support_ticket_intelligence.sh`  Git Bash/Linux/Mac: regenerates this project and deploys it
- `agentforce/subagent-config.md`  copy/paste text for the Agentforce part

## Prerequisites
1. Node.js + Salesforce CLI:  `npm install --global @salesforce/cli`
2. Log in once:  `sf org login web --alias myorg --set-default`

## Deploy (run from the folder containing sfdx-project.json)
    deploy.bat myorg --seed

Or step by step:

    sf project deploy start --source-dir force-app --wait 30 --target-org myorg
    sf org assign permset --name Support_Ticket_Intelligence_Access --target-org myorg
    sf apex run --file scripts\seed.apex --target-org myorg        (once only)
    sf apex run --file scripts\test_flow.apex --target-org myorg   (look for 3 RESULT lines)

## Manual steps after deploy (Setup UI)
1. Setup > Flows > "Support Ticket Intelligence" must be Active.
2. Enable Agentforce: Setup > Agentforce Default > Get Started > Turn On > Confirm.
   Then Setup > Agents > enable the agent (Default Agent appears).
3. Open Default Agent > Open in Builder > New (subagent/topic) > Next.
   Fill the fields from `agentforce/subagent-config.md`.
4. In the subagent add an Action of type Flow > "Support Ticket Intelligence".
   Use the action description, loading text and input settings from the same file.
5. Setup > Permission Sets > Support Ticket Intelligence Access > Manage Assignments:
   add the agent's user (so the flow can read tickets). Find that user in Setup > Agents >
   Default Agent > Settings (Agent User). The permission set also grants Account/Contact read,
   Task create, Run Flows and access to the flow.
6. Save, Activate the agent, and test in the preview panel with the test prompts.

## Notes
- Ticket Number is the object's Name field (auto number TKT-{0000}).
- Flow also handles "account/ticket not found" and flags SLA risk when a ticket is older than 2 days.
