#!/usr/bin/env bash
# =============================================================================
# Customer Support Ticket Priority Prediction - Salesforce CLI automation
#
# Builds an SFDX project and deploys, using the Salesforce CLI (`sf`):
#   * Custom object  Support_Ticket_Intelligence__c  + all 10 fields
#   * Auto-launched flow  Support_Ticket_Intelligence  (Agentforce-ready)
#   * Page layout + permission set (field access) assigned to your user
#   * Optional: sample data + a test run of the flow through Apex
#
# Usage:
#   ./setup_support_ticket_intelligence.sh [-o <org-alias>] [--seed] [--generate-only]
#
#   -o, --org        Alias/username of the org (default: your default target-org)
#   --seed           Insert sample Accounts + tickets and test the flow (run once)
#   --generate-only  Only create the project files, do not deploy
# =============================================================================
set -eo pipefail

PROJECT_DIR="support-ticket-intelligence"
API_VERSION="62.0"
OBJ="Support_Ticket_Intelligence__c"
FLOW_NAME="Support_Ticket_Intelligence"
PERMSET="Support_Ticket_Intelligence_Access"

ORG=""
SEED=false
DEPLOY=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--org)         ORG="$2"; shift 2 ;;
    --seed)           SEED=true; shift ;;
    --generate-only)  DEPLOY=false; shift ;;
    -h|--help)        sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ORG_ARGS=()
if [[ -n "$ORG" ]]; then ORG_ARGS=(--target-org "$ORG"); fi

if $DEPLOY; then
  command -v sf >/dev/null 2>&1 || {
    echo "Salesforce CLI not found. Install it with: npm install --global @salesforce/cli"
    exit 1
  }
fi

# -----------------------------------------------------------------------------
# 1. Project skeleton
# -----------------------------------------------------------------------------
echo ">> Generating project in ./$PROJECT_DIR"
BASE="$PROJECT_DIR/force-app/main/default"
OBJ_DIR="$BASE/objects/$OBJ"
FIELDS="$OBJ_DIR/fields"
mkdir -p "$FIELDS" "$BASE/flows" "$BASE/layouts" "$BASE/permissionsets" "$PROJECT_DIR/scripts"

cat > "$PROJECT_DIR/sfdx-project.json" <<EOF
{
  "packageDirectories": [{ "path": "force-app", "default": true }],
  "name": "support-ticket-intelligence",
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "$API_VERSION"
}
EOF

# -----------------------------------------------------------------------------
# 2. Custom object  (Name field = Ticket Number, auto number TKT-{0000})
# -----------------------------------------------------------------------------
cat > "$OBJ_DIR/$OBJ.object-meta.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Support Ticket Intelligence</label>
    <pluralLabel>Support Ticket Intelligence</pluralLabel>
    <description>Customer support tickets with AI-driven priority and assignment</description>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
    <enableActivities>true</enableActivities>
    <enableReports>true</enableReports>
    <enableHistory>false</enableHistory>
    <enableSearch>true</enableSearch>
    <nameField>
        <label>Ticket Number</label>
        <type>AutoNumber</type>
        <displayFormat>TKT-{0000}</displayFormat>
        <startingNumber>1</startingNumber>
    </nameField>
</CustomObject>
EOF

# -----------------------------------------------------------------------------
# 3. Fields
# -----------------------------------------------------------------------------
HDR='<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">'

# lookup <api> <label> <referenceTo> <relationshipName> <relationshipLabel>
lookup() {
  cat > "$FIELDS/$1.field-meta.xml" <<EOF
$HDR
    <fullName>$1</fullName>
    <label>$2</label>
    <type>Lookup</type>
    <referenceTo>$3</referenceTo>
    <relationshipName>$4</relationshipName>
    <relationshipLabel>$5</relationshipLabel>
    <deleteConstraint>SetNull</deleteConstraint>
    <required>false</required>
</CustomField>
EOF
}

# picklist <api> <label> <default-or-empty> <values...>
picklist() {
  local api="$1" label="$2" def="$3"; shift 3
  {
    cat <<EOF
$HDR
    <fullName>$api</fullName>
    <label>$label</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
EOF
    local v d
    for v in "$@"; do
      d=false
      if [[ -n "$def" && "$v" == "$def" ]]; then d=true; fi
      printf '            <value>\n                <fullName>%s</fullName>\n                <default>%s</default>\n                <label>%s</label>\n            </value>\n' "$v" "$d" "$v"
    done
    printf '        </valueSetDefinition>\n    </valueSet>\n</CustomField>\n'
  } > "$FIELDS/$api.field-meta.xml"
}

lookup Customer__c "Customer" Account "Support_Tickets" "Support Tickets"
lookup Contact__c  "Contact"  Contact "Support_Tickets" "Support Tickets"
lookup Assigned_To__c "Assigned To" User "Assigned_Support_Tickets" "Assigned Support Tickets"

picklist Issue_Type__c      "Issue Type"     ""    Technical Billing General
picklist Priority_Level__c  "Priority Level" ""    Low Medium High
picklist Status__c          "Status"         "New" New "In Progress" Resolved

cat > "$FIELDS/Description__c.field-meta.xml" <<EOF
$HDR
    <fullName>Description__c</fullName>
    <label>Description</label>
    <type>LongTextArea</type>
    <length>32768</length>
    <visibleLines>6</visibleLines>
</CustomField>
EOF

cat > "$FIELDS/Created_Date__c.field-meta.xml" <<EOF
$HDR
    <fullName>Created_Date__c</fullName>
    <label>Created Date</label>
    <type>Date</type>
    <defaultValue>TODAY()</defaultValue>
    <required>false</required>
</CustomField>
EOF

cat > "$FIELDS/SLA_Breach_Risk__c.field-meta.xml" <<EOF
$HDR
    <fullName>SLA_Breach_Risk__c</fullName>
    <label>SLA Breach Risk</label>
    <type>Checkbox</type>
    <defaultValue>false</defaultValue>
</CustomField>
EOF

cat > "$FIELDS/Resolution_Time__c.field-meta.xml" <<EOF
$HDR
    <fullName>Resolution_Time__c</fullName>
    <label>Resolution Time (hrs)</label>
    <type>Number</type>
    <precision>18</precision>
    <scale>2</scale>
    <required>false</required>
</CustomField>
EOF

FIELD_LIST="Customer__c Contact__c Issue_Type__c Description__c Priority_Level__c Status__c Created_Date__c Assigned_To__c SLA_Breach_Risk__c Resolution_Time__c"

# -----------------------------------------------------------------------------
# 4. Page layout
# -----------------------------------------------------------------------------
{
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Layout xmlns="http://soap.sforce.com/2006/04/metadata">
    <layoutSections>
        <customLabel>false</customLabel>
        <detailHeading>false</detailHeading>
        <editHeading>true</editHeading>
        <label>Ticket Information</label>
        <layoutColumns>
            <layoutItems><behavior>Readonly</behavior><field>Name</field></layoutItems>
EOF
  for f in Customer__c Contact__c Issue_Type__c Description__c Resolution_Time__c; do
    printf '            <layoutItems><behavior>Edit</behavior><field>%s</field></layoutItems>\n' "$f"
  done
  printf '        </layoutColumns>\n        <layoutColumns>\n'
  for f in Priority_Level__c Status__c Created_Date__c Assigned_To__c SLA_Breach_Risk__c; do
    printf '            <layoutItems><behavior>Edit</behavior><field>%s</field></layoutItems>\n' "$f"
  done
  cat <<'EOF'
        </layoutColumns>
        <style>TwoColumnsTopToBottom</style>
    </layoutSections>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>
EOF
} > "$BASE/layouts/${OBJ}-Support Ticket Layout.layout-meta.xml"

# -----------------------------------------------------------------------------
# 5. Permission set (object + field access)
# -----------------------------------------------------------------------------
{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Support Ticket Intelligence Access</label>
    <description>Access to Support Ticket Intelligence object and fields</description>
    <hasActivationRequired>false</hasActivationRequired>
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>$OBJ</object>
        <viewAllRecords>true</viewAllRecords>
    </objectPermissions>
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Account</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Contact</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Task</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
EOF
  for f in $FIELD_LIST; do
    printf '    <fieldPermissions>\n        <editable>true</editable>\n        <field>%s.%s</field>\n        <readable>true</readable>\n    </fieldPermissions>\n' "$OBJ" "$f"
  done
  cat <<'EOF'
    <flowAccesses>
        <enabled>true</enabled>
        <flow>Support_Ticket_Intelligence</flow>
    </flowAccesses>
    <userPermissions>
        <enabled>true</enabled>
        <name>RunFlow</name>
    </userPermissions>
</PermissionSet>
EOF
} > "$BASE/permissionsets/$PERMSET.permissionset-meta.xml"

# -----------------------------------------------------------------------------
# 6. Auto-launched flow
#    Input : varAccountName
#    Output: varAccountId, varTicketId, varPriorityLevel, varAssignedTo, varActionMessage
# -----------------------------------------------------------------------------
cat <<'EOF' | sed "s/__API_VERSION__/$API_VERSION/" > "$BASE/flows/$FLOW_NAME.flow-meta.xml"
<?xml version="1.0" encoding="UTF-8"?>
<Flow xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>__API_VERSION__</apiVersion>
    <assignments>
        <name>Store_Account_Id</name>
        <label>Store Account Id</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varAccountId</assignToReference>
            <operator>Assign</operator>
            <value>
                <elementReference>Get_Account.Id</elementReference>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>Get_Ticket</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Store_Ticket_Id</name>
        <label>Store Ticket Id</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varTicketId</assignToReference>
            <operator>Assign</operator>
            <value>
                <elementReference>Get_Ticket.Id</elementReference>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>Analyze_Description</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_High_Priority</name>
        <label>Set High Priority</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varPriorityLevel</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>High</stringValue>
            </value>
        </assignmentItems>
        <assignmentItems>
            <assignToReference>varActionMessage</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>High priority ticket detected. Assigned to senior agent.</stringValue>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>Is_High_Priority</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_Medium_Priority</name>
        <label>Set Medium Priority</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varPriorityLevel</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Medium</stringValue>
            </value>
        </assignmentItems>
        <assignmentItems>
            <assignToReference>varActionMessage</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Ticket marked as medium priority. Will be handled shortly.</stringValue>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>Is_High_Priority</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_Low_Priority</name>
        <label>Set Low Priority</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varPriorityLevel</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Low</stringValue>
            </value>
        </assignmentItems>
        <assignmentItems>
            <assignToReference>varActionMessage</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Tickets are low priority and queued for processing.</stringValue>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>Is_High_Priority</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_Senior_Agent</name>
        <label>Set Senior Agent</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varAssignedTo</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Senior Support Agent</stringValue>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>SLA_Risk</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_Standard_Agent</name>
        <label>Set Standard Agent</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varAssignedTo</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>Support Agent</stringValue>
            </value>
        </assignmentItems>
        <connector>
            <targetReference>SLA_Risk</targetReference>
        </connector>
    </assignments>
    <assignments>
        <name>Set_Not_Found_Message</name>
        <label>Set Not Found Message</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignmentItems>
            <assignToReference>varActionMessage</assignToReference>
            <operator>Assign</operator>
            <value>
                <stringValue>No matching account or support ticket was found.</stringValue>
            </value>
        </assignmentItems>
    </assignments>
    <decisions>
        <name>Account_Found</name>
        <label>Account Found</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <defaultConnector>
            <targetReference>Set_Not_Found_Message</targetReference>
        </defaultConnector>
        <defaultConnectorLabel>No Account</defaultConnectorLabel>
        <rules>
            <name>Account_Exists</name>
            <conditionLogic>and</conditionLogic>
            <conditions>
                <leftValueReference>Get_Account</leftValueReference>
                <operator>IsNull</operator>
                <rightValue>
                    <booleanValue>false</booleanValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Store_Account_Id</targetReference>
            </connector>
            <label>Account Exists</label>
        </rules>
    </decisions>
    <decisions>
        <name>Ticket_Found</name>
        <label>Ticket Found</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <defaultConnector>
            <targetReference>Set_Not_Found_Message</targetReference>
        </defaultConnector>
        <defaultConnectorLabel>No Ticket</defaultConnectorLabel>
        <rules>
            <name>Ticket_Exists</name>
            <conditionLogic>and</conditionLogic>
            <conditions>
                <leftValueReference>Get_Ticket</leftValueReference>
                <operator>IsNull</operator>
                <rightValue>
                    <booleanValue>false</booleanValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Store_Ticket_Id</targetReference>
            </connector>
            <label>Ticket Exists</label>
        </rules>
    </decisions>
    <decisions>
        <name>Analyze_Description</name>
        <label>Analyze Description</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <defaultConnector>
            <targetReference>Set_Low_Priority</targetReference>
        </defaultConnector>
        <defaultConnectorLabel>Low Priority</defaultConnectorLabel>
        <rules>
            <name>High_Priority</name>
            <conditionLogic>or</conditionLogic>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>urgent</stringValue>
                </rightValue>
            </conditions>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>not working</stringValue>
                </rightValue>
            </conditions>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>failure</stringValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Set_High_Priority</targetReference>
            </connector>
            <label>High Priority</label>
        </rules>
        <rules>
            <name>Medium_Priority</name>
            <conditionLogic>or</conditionLogic>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>issue</stringValue>
                </rightValue>
            </conditions>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>slow</stringValue>
                </rightValue>
            </conditions>
            <conditions>
                <leftValueReference>Get_Ticket.Description__c</leftValueReference>
                <operator>Contains</operator>
                <rightValue>
                    <stringValue>delay</stringValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Set_Medium_Priority</targetReference>
            </connector>
            <label>Medium Priority</label>
        </rules>
    </decisions>
    <decisions>
        <name>Is_High_Priority</name>
        <label>Is High Priority</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <defaultConnector>
            <targetReference>Set_Standard_Agent</targetReference>
        </defaultConnector>
        <defaultConnectorLabel>Not High</defaultConnectorLabel>
        <rules>
            <name>High_Yes</name>
            <conditionLogic>and</conditionLogic>
            <conditions>
                <leftValueReference>varPriorityLevel</leftValueReference>
                <operator>EqualTo</operator>
                <rightValue>
                    <stringValue>High</stringValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Create_Urgent_Task</targetReference>
            </connector>
            <label>Yes</label>
        </rules>
    </decisions>
    <decisions>
        <name>SLA_Risk</name>
        <label>SLA Risk</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <defaultConnectorLabel>No Risk</defaultConnectorLabel>
        <rules>
            <name>SLA_At_Risk</name>
            <conditionLogic>and</conditionLogic>
            <conditions>
                <leftValueReference>formulaSlaRisk</leftValueReference>
                <operator>EqualTo</operator>
                <rightValue>
                    <booleanValue>true</booleanValue>
                </rightValue>
            </conditions>
            <connector>
                <targetReference>Flag_SLA_Risk</targetReference>
            </connector>
            <label>At Risk</label>
        </rules>
    </decisions>
    <description>Finds the latest ticket for an account, sets priority from keywords, creates a task for urgent tickets.</description>
    <environments>Default</environments>
    <formulas>
        <name>formulaSlaRisk</name>
        <dataType>Boolean</dataType>
        <expression>AND(NOT(ISBLANK({!Get_Ticket.Created_Date__c})), {!Get_Ticket.Created_Date__c} &lt; ({!$Flow.CurrentDate} - 2))</expression>
    </formulas>
    <interviewLabel>Support Ticket Intelligence {!$Flow.CurrentDateTime}</interviewLabel>
    <label>Support Ticket Intelligence</label>
    <processMetadataValues>
        <name>CanvasMode</name>
        <value>
            <stringValue>AUTO_LAYOUT_CANVAS</stringValue>
        </value>
    </processMetadataValues>
    <processType>AutoLaunchedFlow</processType>
    <recordCreates>
        <name>Create_Urgent_Task</name>
        <label>Create Urgent Task</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <connector>
            <targetReference>Set_Senior_Agent</targetReference>
        </connector>
        <inputAssignments>
            <field>Subject</field>
            <value>
                <stringValue>Urgent Ticket Handling</stringValue>
            </value>
        </inputAssignments>
        <inputAssignments>
            <field>WhatId</field>
            <value>
                <elementReference>varTicketId</elementReference>
            </value>
        </inputAssignments>
        <inputAssignments>
            <field>Priority</field>
            <value>
                <stringValue>High</stringValue>
            </value>
        </inputAssignments>
        <inputAssignments>
            <field>Status</field>
            <value>
                <stringValue>Not Started</stringValue>
            </value>
        </inputAssignments>
        <object>Task</object>
    </recordCreates>
    <recordLookups>
        <name>Get_Account</name>
        <label>Get Account</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignNullValuesIfNoRecordsFound>false</assignNullValuesIfNoRecordsFound>
        <connector>
            <targetReference>Account_Found</targetReference>
        </connector>
        <filterLogic>and</filterLogic>
        <filters>
            <field>Name</field>
            <operator>EqualTo</operator>
            <value>
                <elementReference>varAccountName</elementReference>
            </value>
        </filters>
        <getFirstRecordOnly>true</getFirstRecordOnly>
        <object>Account</object>
        <sortField>CreatedDate</sortField>
        <sortOrder>Desc</sortOrder>
        <storeOutputAutomatically>true</storeOutputAutomatically>
    </recordLookups>
    <recordLookups>
        <name>Get_Ticket</name>
        <label>Get Ticket</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignNullValuesIfNoRecordsFound>false</assignNullValuesIfNoRecordsFound>
        <connector>
            <targetReference>Ticket_Found</targetReference>
        </connector>
        <filterLogic>and</filterLogic>
        <filters>
            <field>Customer__c</field>
            <operator>EqualTo</operator>
            <value>
                <elementReference>varAccountId</elementReference>
            </value>
        </filters>
        <getFirstRecordOnly>true</getFirstRecordOnly>
        <object>Support_Ticket_Intelligence__c</object>
        <sortField>CreatedDate</sortField>
        <sortOrder>Desc</sortOrder>
        <storeOutputAutomatically>true</storeOutputAutomatically>
    </recordLookups>
    <recordUpdates>
        <name>Flag_SLA_Risk</name>
        <label>Flag SLA Risk</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <filterLogic>and</filterLogic>
        <filters>
            <field>Id</field>
            <operator>EqualTo</operator>
            <value>
                <elementReference>varTicketId</elementReference>
            </value>
        </filters>
        <inputAssignments>
            <field>SLA_Breach_Risk__c</field>
            <value>
                <booleanValue>true</booleanValue>
            </value>
        </inputAssignments>
        <object>Support_Ticket_Intelligence__c</object>
    </recordUpdates>
    <start>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <connector>
            <targetReference>Get_Account</targetReference>
        </connector>
    </start>
    <status>Active</status>
    <variables>
        <name>varAccountName</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>true</isInput>
        <isOutput>false</isOutput>
    </variables>
    <variables>
        <name>varAccountId</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>false</isInput>
        <isOutput>true</isOutput>
    </variables>
    <variables>
        <name>varTicketId</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>false</isInput>
        <isOutput>true</isOutput>
    </variables>
    <variables>
        <name>varPriorityLevel</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>false</isInput>
        <isOutput>true</isOutput>
    </variables>
    <variables>
        <name>varAssignedTo</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>false</isInput>
        <isOutput>true</isOutput>
    </variables>
    <variables>
        <name>varActionMessage</name>
        <dataType>String</dataType>
        <isCollection>false</isCollection>
        <isInput>false</isInput>
        <isOutput>true</isOutput>
    </variables>
</Flow>
EOF

# -----------------------------------------------------------------------------
# 7. Optional sample data + flow test (Anonymous Apex)
# -----------------------------------------------------------------------------
cat > "$PROJECT_DIR/scripts/seed.apex" <<'EOF'
Account a1 = new Account(Name = 'Acme Urgent Corp');
Account a2 = new Account(Name = 'Globex Slow Corp');
Account a3 = new Account(Name = 'Initech General Corp');
insert new List<Account>{ a1, a2, a3 };

insert new List<Support_Ticket_Intelligence__c>{
    new Support_Ticket_Intelligence__c(Customer__c = a1.Id, Issue_Type__c = 'Technical',
        Description__c = 'Production server is not working, urgent fix needed.',
        Created_Date__c = Date.today().addDays(-3)),
    new Support_Ticket_Intelligence__c(Customer__c = a2.Id, Issue_Type__c = 'Technical',
        Description__c = 'Dashboard is slow to load since yesterday.'),
    new Support_Ticket_Intelligence__c(Customer__c = a3.Id, Issue_Type__c = 'General',
        Description__c = 'How do I change my display name?')
};
EOF

cat > "$PROJECT_DIR/scripts/test_flow.apex" <<'EOF'
for (String n : new List<String>{ 'Acme Urgent Corp', 'Globex Slow Corp', 'Initech General Corp' }) {
    Map<String, Object> inputs = new Map<String, Object>{ 'varAccountName' => n };
    Flow.Interview fi = Flow.Interview.createInterview('Support_Ticket_Intelligence', inputs);
    fi.start();
    System.debug('RESULT | ' + n + ' | ' + fi.getVariableValue('varPriorityLevel')
        + ' | ' + fi.getVariableValue('varAssignedTo')
        + ' | ' + fi.getVariableValue('varActionMessage'));
}
EOF

echo ">> Project files generated."

if ! $DEPLOY; then
  echo ">> --generate-only set; skipping deploy."
  exit 0
fi

# -----------------------------------------------------------------------------
# 8. Deploy with Salesforce CLI
# -----------------------------------------------------------------------------
cd "$PROJECT_DIR"

if [[ -z "$ORG" ]]; then
  if ! sf config get target-org --json 2>/dev/null | grep -q '"value"'; then
    echo ">> No default org set - opening browser login (alias: ticket-org)"
    sf org login web --alias ticket-org --set-default
  fi
fi

echo ">> Deploying metadata..."
sf project deploy start --source-dir force-app --wait 30 "${ORG_ARGS[@]}"

echo ">> Assigning permission set $PERMSET to current user..."
sf org assign permset --name "$PERMSET" "${ORG_ARGS[@]}" || echo "   (already assigned or not needed)"

if $SEED; then
  echo ">> Inserting sample data..."
  sf apex run --file scripts/seed.apex "${ORG_ARGS[@]}" > /dev/null
  echo ">> Testing the flow..."
  sf apex run --file scripts/test_flow.apex "${ORG_ARGS[@]}" | grep "RESULT" || true
fi

echo
echo "Done. Next: finish the Agentforce part in Setup (enable Agentforce, create the"
echo "'Support Ticket Priority Analysis' subagent, add the '$FLOW_NAME' flow as an action)."
echo "Open the org:  sf org open ${ORG_ARGS[*]}"
