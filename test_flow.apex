for (String n : new List<String>{ 'Acme Urgent Corp', 'Globex Slow Corp', 'Initech General Corp' }) {
    Map<String, Object> inputs = new Map<String, Object>{ 'varAccountName' => n };
    Flow.Interview fi = Flow.Interview.createInterview('Support_Ticket_Intelligence', inputs);
    fi.start();
    System.debug('RESULT | ' + n + ' | ' + fi.getVariableValue('varPriorityLevel')
        + ' | ' + fi.getVariableValue('varAssignedTo')
        + ' | ' + fi.getVariableValue('varActionMessage'));
}
