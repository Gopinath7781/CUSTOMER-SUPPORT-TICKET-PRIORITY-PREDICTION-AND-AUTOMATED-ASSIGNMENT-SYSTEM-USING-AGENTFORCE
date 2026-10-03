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
