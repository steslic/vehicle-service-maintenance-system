"""Revision-007 business APIs and native entitlements on disposable MySQL only."""

import hashlib
import json
import re
import subprocess
import threading

import mysql_test_support as support
import test_error_handling as errors
import test_reference_identity as identity
from operation_contract import OPERATIONS
from database import Session
from migrate import schema_fingerprints


class ProcedureOperationTests(support.DisposableMySQLTestCase):
    actor = identity.ReferenceIdentityTests.actor
    remove_demo_accounts = identity.ReferenceIdentityTests.remove_demo_accounts

    def setUp(self):
        super().setUp()
        self.addCleanup(self.remove_demo_accounts)
        self.result = self.build('--with-demo-accounts')
        self.assert_success(self.result)
        self.assertIn('PASS\t45', self.result.stdout)
        self.assertIn('CONSOLIDATED REVISION 007: VERIFIED', self.result.stdout)

    def value(self, sql):
        return self.scalar(f'USE `{self.database}`; ' + sql)

    def invoke(self, name, *args, user='sa_amy', person=None, error=None):
        def literal(value):
            if value is None:
                return 'NULL'
            if isinstance(value, (int, float)):
                return str(value)
            return support.accounts.literal(value)
        return self.actor(user, 'CALL ' + name + '(' + ','.join(literal(x) for x in (*args, person)) + ');', error)

    def book(self, vehicle=5, day=150):
        return int(self.actor('sa_amy', f"CALL sp_CreateServiceAppointment(1,{vehicle},1,NULL,"
            f"TIMESTAMP(CURDATE()+INTERVAL {day} DAY,'08:00:00'),'Procedure workflow',60);"))

    def open_repair(self, appointment):
        self.invoke('sp_SetServiceAppointmentStatus', appointment, 'Checked In', None)
        self.invoke('sp_SetServiceAppointmentStatus', appointment, 'In Progress', None)
        repair = int(self.invoke('sp_CreateRepair', appointment, self.value('SELECT UTC_TIMESTAMP();'),
            'Oil Change', 'Procedure repair', 0.5))
        self.invoke('sp_SetRepairStatus', repair, 'In Progress', user='tech_ben')
        return repair

    def test_current_installation_registers_revision_separately_from_historical_coverage(self):
        self.assertEqual(self.value("SELECT GROUP_CONCAT(DISTINCT status),COUNT(applied_at),COUNT(*) FROM schema_migrations;"), 'covered\t0\t6')
        self.assertEqual(self.value("SELECT revision,status,installed_at IS NOT NULL FROM schema_revisions;"), '7\tinstalled\t1')
        self.assertEqual(self.value("SELECT migration_version IS NULL,revision_version FROM schema_object_versions WHERE object_name='sp_createcustomer';"), '1\t7')
        self.assertEqual(self.value("SELECT migration_version,revision_version FROM schema_object_versions WHERE object_name='fn_errorclass';"), '6\t7')
        self.assertEqual(self.value('SELECT COUNT(*) FROM schema_object_versions;'), '276')
        self.assertEqual(self.value("SELECT migration_version IS NULL,revision_version FROM schema_object_versions WHERE object_name='sp_tryrecordrejecteddiagnostic';"), '1\t7')
        self.assertEqual(self.value("SELECT SECURITY_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_NAME='sp_TryRecordRejectedDiagnostic';"), 'DEFINER')
        for table,column in [('ROUTINES','ROUTINE_SCHEMA'),('TRIGGERS','TRIGGER_SCHEMA')]:
            self.assertEqual(self.value(f"SELECT GROUP_CONCAT(DISTINCT DEFINER) FROM information_schema.{table} WHERE {column}=DATABASE();"),'vsm_developer@localhost')
        self.assertNotIn('WITH GRANT OPTION',self.scalar('SHOW GRANTS;'))
        self.assertEqual(self.admin_scalar("SELECT COUNT(*) FROM mysql.procs_priv WHERE User='vsm_developer' AND FIND_IN_SET('Grant',Proc_priv);"),'0')
        self.assertEqual(self.value("SELECT fn_ApplicationErrorID(53007),fn_ErrorClass(53007,'45000',FALSE);"), 'VSM_RECORD_NOT_FOUND\tnot_found')
        self.assertNotIn('OPERATION migration', self.result.stdout)
        customer = int(self.invoke('sp_CreateCustomer', 'API customer', None, None))
        self.assertEqual(self.value(f'SELECT Name FROM Customer WHERE CustomerID={customer};'), 'API customer')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')

    def test_all_native_grants_are_read_or_authorized_execute_only(self):
        contract = json.loads((support.ROOT/'sql/consolidated/007_procedure_only.json').read_text())
        for user, role in [('sa_amy','role_service_advisor'),('tech_ben','role_technician'),('mgr_mike','role_manager')]:
            password = {'sa_amy':'Advisor#2026','tech_ben':'Tech#2026','mgr_mike':'Manager#2026'}[user]
            grants = self.account_sql(user,password,f"SHOW GRANTS FOR CURRENT_USER USING '{role}';").stdout
            actual = {'tables':{},'procedures':[]}
            for line in grants.splitlines():
                match = re.match(r'GRANT (.*?) ON (.*?) TO ',line)
                if not match or match[1]=='USAGE':
                    continue
                privilege, obj = match.groups()
                name = obj.split('.')[-1].strip('`').lower()
                if obj.startswith('PROCEDURE '):
                    self.assertEqual(privilege,'EXECUTE',line)
                    actual['procedures'].append(name)
                else:
                    self.assertEqual(privilege,'SELECT',line)
                    actual['tables'][name]='Select'
            actual['procedures'].sort()
            self.assertEqual(actual,contract['native_roles'][role])

    def test_every_api_has_matching_role_metadata_and_native_entry_gates(self):
        users={'Service Advisor':'sa_amy','Technician':'tech_ben','Manager':'mgr_mike'}
        for name, spec in OPERATIONS.items():
            for role,user in users.items():
                with self.subTest(procedure=name,role=role):
                    # Invalid data exercises the entry gate without changing business rows.
                    password={'sa_amy':'Advisor#2026','tech_ben':'Tech#2026','mgr_mike':'Manager#2026'}[user]
                    args=','.join(['NULL']*(len(spec['params'])+1))
                    result=self.account_sql(user,password,f'USE `{self.database}`; CALL {name}({args});',check=False)
                    self.assertNotEqual(result.returncode,0,result.stdout)
                    if role in spec['roles']:
                        self.assertNotIn('ERROR 1370',result.stderr)
                        self.assertNotIn('ERROR 52006',result.stderr)
                        self.assertNotIn('ERROR 52001',result.stderr)
                    else:
                        self.assertIn('ERROR 1370',result.stderr)
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def test_direct_writes_are_denied_on_every_business_table_for_every_role(self):
        keys={'Customer':'CustomerID','Vehicle':'VehicleID','Technician':'TechnicianID','Part':'PartID',
              'UserAccount':'UserID','ServiceAppointment':'AppointmentID','Repair':'RepairID',
              'RepairEstimate':'EstimateID','EstimateLineItem':'EstimateID','Invoice':'InvoiceID',
              'InvoiceLineItem':'InvoiceLineItemID','PartsUsage':'PartsUsageID'}
        for user in ['sa_amy','tech_ben','mgr_mike']:
            for table,key in keys.items():
                for sql in [f'INSERT INTO {table} ({key}) SELECT 1 WHERE FALSE;',
                            f'UPDATE {table} SET {key}={key} WHERE FALSE;',f'DELETE FROM {table} WHERE FALSE;']:
                    with self.subTest(user=user,table=table,sql=sql):
                        self.actor(user,sql,'ERROR 1142')

    def test_filtered_writable_view_cannot_bypass_procedure_only_access(self):
        self.actor('tech_ben',"UPDATE vw_MyRepairs SET Status='In Progress' WHERE RepairID=6;",'ERROR 1142')
        self.actor('tech_ben','SELECT COUNT(*) FROM vw_MyRepairs;')
        self.actor('tech_ben','SELECT * FROM Repair;','ERROR 1142')
        self.actor('tech_ben','SELECT * FROM ServiceAppointment;','ERROR 1142')

    def test_protected_logs_histories_context_and_internal_writers_remain_inaccessible(self):
        for user in ['sa_amy','tech_ben','mgr_mike']:
            for table in ['AuditLog','CustomerHistory','TemporalEvent','TemporalWriteContext','OperationContext']:
                self.actor(user,f'DELETE FROM {table} WHERE FALSE;','ERROR 1142')
            self.actor(user,"CALL sp_RecordRejectedDiagnostic(NULL,'x','x',NULL,'x',NULL,NULL,'45000',51001,'not_started');",'ERROR 1370')
            self.actor(user,"CALL sp_TryRecordRejectedDiagnostic(NULL,'x','x',NULL,'x',NULL,NULL,'45000',51001,'not_started');",'ERROR 1370')
            self.actor(user,"CALL sp_ResolveActor(NULL,NULL,@person);",'ERROR 1370')

    def test_customer_vehicle_and_technician_interfaces_preserve_full_editable_fields(self):
        customer=int(self.invoke('sp_CreateCustomer','New customer','555-1212','person@example.invalid'))
        self.invoke('sp_UpdateCustomer',customer,'Changed customer',None,None)
        vehicle=int(self.invoke('sp_CreateVehicle',customer,'1TEST234567890123','Make','Model',2024))
        self.invoke('sp_UpdateVehicle',vehicle,customer,'1TEST234567890123','Make2','Model2',2025)
        technician=int(self.invoke('sp_CreateTechnician','New technician',None,'tech@example.invalid',1,user='mgr_mike'))
        self.invoke('sp_UpdateTechnician',technician,'Changed technician','555-3434',None,0,user='mgr_mike')
        self.assertEqual(self.value(f'SELECT Name,Phone IS NULL,Email IS NULL FROM Customer WHERE CustomerID={customer};'),'Changed customer\t1\t1')
        self.assertEqual(self.value(f'SELECT Make,Model,Year FROM Vehicle WHERE VehicleID={vehicle};'),'Make2\tModel2\t2025')
        self.assertEqual(self.value(f'SELECT Name,ActiveStatus FROM Technician WHERE TechnicianID={technician};'),'Changed technician\t0')
        self.assertEqual(self.value(f'SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID={customer};'),'2')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def test_inventory_operations_are_manager_only_and_preserve_reasons_and_constraints(self):
        part=int(self.invoke('sp_CreatePart','API-01','API part',1.5,3.5,2,1,10,user='mgr_mike'))
        self.invoke('sp_UpdatePart',part,'API-01','Renamed part',2.5,4.5,3,1,user='mgr_mike')
        self.invoke('sp_AdjustPartInventory',part,7,'Stock count',user='mgr_mike')
        self.assertEqual(self.value(f'SELECT QuantityOnHand FROM Part WHERE PartID={part};'),'7')
        self.assertEqual(self.value(f"SELECT HistoryReason,HistoryUserID,HistorySessionAccount FROM PartHistory WHERE PartID={part} AND HistoryIsCurrent=1;"),'Stock count\t1\tmgr_mike@localhost')
        self.invoke('sp_AdjustPartInventory',part,6,None,user='mgr_mike',error='VSM_INVENTORY_REASON_REQUIRED')
        self.invoke('sp_AdjustPartInventory',part,-1,'Invalid stock',user='mgr_mike',error='ERROR 3819')
        self.assertEqual(self.value(f'SELECT QuantityOnHand FROM Part WHERE PartID={part};'),'7')
        self.invoke('sp_AdjustPartInventory',part,6,'Denied',error='ERROR 1370')

    def test_appointment_updates_preserve_overlap_reassignment_and_cancellation_rules(self):
        appointment=self.book()
        when=self.value(f'SELECT AppointmentDateTime FROM ServiceAppointment WHERE AppointmentID={appointment};')
        self.invoke('sp_UpdateServiceAppointment',appointment,2,when,'Reassigned',90)
        self.assertEqual(self.value(f'SELECT TechnicianID FROM ServiceAppointment WHERE AppointmentID={appointment};'),'2')
        second=self.book(vehicle=1,day=151)
        self.invoke('sp_UpdateServiceAppointment',second,2,when,'Overlap',60,error='VSM_SCHEDULE_CONFLICT')
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Cancelled','Customer request')
        self.assertEqual(self.value(f'SELECT Status,CancellationReason,CancellationDate=UTC_DATE() FROM ServiceAppointment WHERE AppointmentID={appointment};'),'Cancelled\tCustomer request\t1')
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Checked In',None,error='VSM_FINAL_STATE_IMMUTABLE')

    def test_complete_repair_workflow_records_inventory_both_identities_and_history(self):
        appointment=self.book();repair=self.open_repair(appointment)
        before=int(self.value('SELECT QuantityOnHand FROM Part WHERE PartID=1;'))
        self.actor('tech_ben',f'CALL sp_CompleteRepair({repair},1,NULL,\'[{{"partId":1,"qty":2}}]\');')
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Completed',None)
        self.assertEqual(self.value(f'SELECT Status,CompletedByTechnicianID FROM Repair WHERE RepairID={repair};'),'Completed\t1')
        self.assertEqual(int(self.value('SELECT QuantityOnHand FROM Part WHERE PartID=1;')),before-2)
        self.assertEqual(self.value(f'SELECT HistoryUserID,HistorySessionAccount,HistoryContextID IS NOT NULL FROM RepairHistory WHERE RepairID={repair} AND HistoryIsCurrent=1;'),'3\ttech_ben@localhost\t1')
        self.assertEqual(self.value(f"SELECT UserID,SessionAccount FROM AuditLog WHERE AffectedEntity='Repair' AND AffectedRecordID={repair} AND Action='Complete' ORDER BY AuditLogID DESC LIMIT 1;"),'3\ttech_ben@localhost')
        self.actor('tech_ben',f'CALL sp_CompleteRepair({repair},1,NULL,NULL);','VSM_RELATED_STATE_CONFLICT')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'),'0')

    def test_technician_cannot_modify_another_repair_even_with_noop_status(self):
        appointment=self.book()
        when=self.value(f'SELECT AppointmentDateTime FROM ServiceAppointment WHERE AppointmentID={appointment};')
        self.invoke('sp_UpdateServiceAppointment',appointment,2,when,'Other technician',60)
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Checked In',None)
        repair=int(self.invoke('sp_CreateRepair',appointment,self.value('SELECT UTC_TIMESTAMP();'),'Diagnostic','Assigned elsewhere',1))
        self.invoke('sp_SetRepairStatus',repair,'Open',user='tech_ben',error='VSM_OPERATION_DENIED')
        self.invoke('sp_SetRepairStatus',repair,'In Progress',user='tech_ben',error='VSM_OPERATION_DENIED')
        self.invoke('sp_UpdateRepair',repair,self.value('SELECT UTC_TIMESTAMP();'),'Diagnostic','Denied',1,user='tech_ben',error='ERROR 1370')
        self.assertEqual(self.value(f'SELECT Status FROM Repair WHERE RepairID={repair};'),'Open')

    def test_manager_supervisor_override_stays_audited_and_does_not_invent_parts_usage(self):
        appointment=self.book();repair=self.open_repair(appointment)
        self.invoke('sp_UpdateRepair',repair,self.value('SELECT UTC_TIMESTAMP();'),'Diagnostic','Supervisor review',1.5,user='mgr_mike')
        before=self.value('SELECT SUM(QuantityOnHand) FROM Part;')
        self.invoke('sp_SetRepairStatus',repair,'Completed',user='mgr_mike')
        self.assertEqual(self.value(f'SELECT Status,CompletedByTechnicianID FROM Repair WHERE RepairID={repair};'),'Completed\t1')
        self.assertEqual(self.value(f'SELECT HistoryUserID,HistorySessionAccount FROM RepairHistory WHERE RepairID={repair} AND HistoryIsCurrent=1;'),'1\tmgr_mike@localhost')
        self.assertEqual(self.value('SELECT SUM(QuantityOnHand) FROM Part;'),before)
        self.assertEqual(self.value(f'SELECT COUNT(*) FROM PartsUsage WHERE RepairID={repair};'),'0')
        self.invoke('sp_SetRepairStatus',repair,'Completed',user='mgr_mike',error='VSM_FINAL_STATE_IMMUTABLE')

    def test_technician_completion_requires_existing_completion_entry_point(self):
        repair=self.open_repair(self.book())
        self.invoke('sp_SetRepairStatus',repair,'Completed',user='tech_ben',error='VSM_COMPLETION_ENTRY_REQUIRED')
        self.assertEqual(self.value(f'SELECT Status FROM Repair WHERE RepairID={repair};'),'In Progress')

    def test_estimate_line_items_decisions_totals_and_finalization(self):
        estimate=int(self.invoke('sp_CreateRepairEstimate',self.book(),self.value('SELECT UTC_DATE();'),0))
        self.invoke('sp_CreateEstimateLineItem',estimate,1,'Labor',2,10)
        self.invoke('sp_UpdateEstimateLineItem',estimate,1,'Labor revised',3,10)
        self.invoke('sp_CreateEstimateLineItem',estimate,2,'Unused',1,5)
        self.invoke('sp_DeleteEstimateLineItem',estimate,2)
        self.invoke('sp_UpdateRepairEstimate',estimate,self.value('SELECT UTC_DATE();'),30)
        self.invoke('sp_SubmitRepairEstimate',estimate)
        self.invoke('sp_DecideRepairEstimate',estimate,'Approved',error='ERROR 1370')
        self.invoke('sp_DecideRepairEstimate',estimate,'Approved',user='mgr_mike')
        self.invoke('sp_FinalizeRepairEstimate',estimate)
        self.assertEqual(self.value(f'SELECT Status,TotalAmount,ApprovedByUserID FROM RepairEstimate WHERE EstimateID={estimate};'),'Finalized\t30.00\t1')
        for name,args in [('sp_UpdateEstimateLineItem',(estimate,1,'Denied',1,1)),('sp_DeleteEstimateLineItem',(estimate,1)),('sp_CreateEstimateLineItem',(estimate,3,'Denied',1,1))]:
            self.invoke(name,*args,error='VSM_FINAL_STATE_IMMUTABLE')

    def test_estimate_rejection_expiration_and_invalid_transition_stay_enforced(self):
        for decision in ['Rejected','Expired']:
            estimate=int(self.invoke('sp_CreateRepairEstimate',self.book(day=150 if decision=='Rejected' else 151),self.value('SELECT UTC_DATE();'),0))
            self.invoke('sp_SubmitRepairEstimate',estimate)
            if decision=='Rejected':self.invoke('sp_DecideRepairEstimate',estimate,decision,user='mgr_mike')
            else:self.invoke('sp_ExpireRepairEstimate',estimate)
            self.invoke('sp_FinalizeRepairEstimate',estimate,error='VSM_INVALID_TRANSITION')
            self.assertEqual(self.value(f'SELECT Status FROM RepairEstimate WHERE EstimateID={estimate};'),decision)

    def test_invoice_line_items_and_finalization_preserve_immutability_and_totals(self):
        appointment=self.book();repair=self.open_repair(appointment)
        self.actor('tech_ben',f'CALL sp_CompleteRepair({repair},1,NULL,NULL);')
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Completed',None)
        invoice=int(self.invoke('sp_CreateInvoice',appointment,self.value('SELECT UTC_DATE();'),0))
        line=int(self.invoke('sp_CreateInvoiceLineItem',invoice,'Labor',1,20).split('\t')[-1])
        self.invoke('sp_UpdateInvoiceLineItem',line,'Labor revised',2,20)
        unused=int(self.invoke('sp_CreateInvoiceLineItem',invoice,'Unused',1,3).split('\t')[-1])
        self.invoke('sp_DeleteInvoiceLineItem',unused)
        self.invoke('sp_FinalizeInvoice',invoice,error='VSM_FINANCIAL_TOTAL_CONFLICT')
        self.invoke('sp_UpdateInvoice',invoice,self.value('SELECT UTC_DATE();'),40)
        self.invoke('sp_FinalizeInvoice',invoice)
        self.assertEqual(self.value(f'SELECT Status,FinalizedByUserID FROM Invoice WHERE InvoiceID={invoice};'),'Finalized\t2')
        self.invoke('sp_DeleteInvoiceLineItem',line,error='VSM_FINAL_STATE_IMMUTABLE')
        self.invoke('sp_UpdateInvoice',invoice,self.value('SELECT UTC_DATE();'),0,error='VSM_FINAL_STATE_IMMUTABLE')

    def test_missing_records_invalid_inputs_and_original_diagnostics_are_stable(self):
        self.invoke('sp_UpdateCustomer',999999,'Missing',None,None,error='ERROR 53007')
        self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,ApplicationErrorID,ErrorClass,TransactionOutcome,UserID,SessionAccount FROM AuditLog WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),'53007\t45000\tVSM_RECORD_NOT_FOUND\tnot_found\trolled_back\t2\tsa_amy@localhost')
        count=self.value('SELECT COUNT(*) FROM Customer;')
        self.invoke('sp_CreateCustomer',None,None,None,error='ERROR 1048')
        self.assertEqual(self.value('SELECT COUNT(*) FROM Customer;'),count)
        self.assertEqual(self.value("SELECT ErrorNumber,ErrorClass FROM AuditLog WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),'1048\tvalidation')
        self.invoke('sp_CreateCustomer','Spoofed',None,None,person=1,error='VSM_ACTOR_MISMATCH')
        self.assertEqual(self.value('SELECT COUNT(*) FROM Customer;'),count)
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def test_role_metadata_still_blocks_a_native_grant_that_would_be_too_broad(self):
        self.admin_sql(f"GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CreateCustomer TO 'tech_ben'@'localhost';")
        self.invoke('sp_CreateCustomer','Denied',None,None,user='tech_ben',error='VSM_OPERATION_DENIED')
        self.assertEqual(self.value("SELECT COUNT(*) FROM Customer WHERE Name='Denied';"),'0')

    def test_service_delegation_is_per_person_and_per_operation(self):
        self.admin_sql(f"CREATE USER 'svc_test'@'localhost' IDENTIFIED BY 'Service#2026'; GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CreateCustomer TO 'svc_test'@'localhost'; GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_UpdateCustomer TO 'svc_test'@'localhost';")
        self.sql(f"INSERT INTO `{self.database}`.DatabasePrincipal(SessionAccount,PrincipalType) VALUES('svc_test@localhost','Service'); INSERT INTO `{self.database}`.PrincipalDelegation(SessionAccount,UserID,ProcedureName) VALUES('svc_test@localhost',2,'sp_CreateCustomer');")
        customer=int(self.invoke('sp_CreateCustomer','Delegated customer',None,None,user='svc_test',person=2))
        self.assertEqual(self.value(f'SELECT HistoryUserID,HistorySessionAccount,HistoryContextID IS NOT NULL FROM CustomerHistory WHERE CustomerID={customer};'),'2\tsvc_test@localhost\t1')
        self.invoke('sp_UpdateCustomer',customer,'Denied',None,None,user='svc_test',person=2,error='VSM_DELEGATION_DENIED')
        self.invoke('sp_CreateCustomer','Denied',None,None,user='svc_test',person=3,error='VSM_DELEGATION_DENIED')
        self.invoke('sp_CreateCustomer','Denied',None,None,user='svc_test',error='VSM_DELEGATION_DENIED')
        self.actor('svc_test','UPDATE Customer SET Name=Name WHERE FALSE;','ERROR 1142')

    def test_history_failure_rolls_back_business_context_and_temporal_state(self):
        before=[self.value(f'SELECT COUNT(*) FROM {table};') for table in ['Customer','CustomerHistory','TemporalEvent']]
        self.sql(f"USE `{self.database}`; CREATE TRIGGER test_HistoryFailure BEFORE INSERT ON CustomerHistory FOR EACH ROW SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO=59001,MESSAGE_TEXT='Injected history failure';")
        self.invoke('sp_CreateCustomer','Must roll back',None,None,error='VSM_HISTORY_INCONSISTENT')
        self.assertEqual([self.value(f'SELECT COUNT(*) FROM {table};') for table in ['Customer','CustomerHistory','TemporalEvent']],before)
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'),'0')

    def test_secondary_logger_failure_preserves_original_error_and_rollback(self):
        self.sql(f"USE `{self.database}`; CREATE TRIGGER test_LoggerFailure BEFORE INSERT ON AuditLog FOR EACH ROW SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO=59999,MESSAGE_TEXT='Injected logger failure';")
        self.invoke('sp_UpdateCustomer',999999,'Missing',None,None,error='ERROR 53007')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def capture_customer_failure(self, requested_actor=None, after_sql=''):
        # Catch inside the restricted session so connection teardown cannot hide failed cleanup.
        self.sql(f"""USE `{self.database}`;
DELIMITER //
CREATE PROCEDURE test_CaptureCustomerFailure(IN p_Actor INT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_State CHAR(5);
    DECLARE v_Number INT;
    DECLARE v_Message TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET STACKED DIAGNOSTICS CONDITION 1 v_State=RETURNED_SQLSTATE,
            v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
        SELECT JSON_OBJECT('state',v_State,'number',v_Number,'message',v_Message,
            'clean',@app_user_id IS NULL AND @adj_reason IS NULL AND @context_id IS NULL);
    END;
    CALL sp_UpdateCustomer(999999,'Missing',NULL,NULL,p_Actor);
END //
DELIMITER ;
""")
        self.admin_sql(f"GRANT EXECUTE ON PROCEDURE `{self.database}`.test_CaptureCustomerFailure TO 'sa_amy'@'localhost';")
        actor = 'NULL' if requested_actor is None else str(requested_actor)
        rows = self.actor('sa_amy', f'CALL test_CaptureCustomerFailure({actor}); ' + after_sql).splitlines()
        return json.loads(rows[0])

    def test_partial_logger_work_is_rolled_back_before_the_connection_is_reused(self):
        self.sql(f"""USE `{self.database}`;
CREATE TABLE LoggerProbe(ID INT PRIMARY KEY);
DELIMITER //
DROP PROCEDURE sp_RecordRejectedDiagnostic //
CREATE PROCEDURE sp_RecordRejectedDiagnostic(IN a INT, IN b VARCHAR(64), IN c VARCHAR(100),
    IN d INT, IN e TEXT, IN f JSON, IN g CHAR(36), IN h CHAR(5), IN i INT, IN j VARCHAR(16))
BEGIN
    INSERT INTO LoggerProbe VALUES(1);
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO=59999,MESSAGE_TEXT='Logger failed after writing';
END //
DELIMITER ;
""")
        diagnostic = self.capture_customer_failure(after_sql="CALL sp_CreateCustomer('After logger failure',NULL,NULL,NULL);")
        self.assertEqual(diagnostic, {'state':'45000','number':53007,'message':'Requested record does not exist','clean':1})
        self.assertEqual(self.value('SELECT COUNT(*) FROM LoggerProbe;'), '0')
        self.assertEqual(self.value("SELECT COUNT(*) FROM Customer WHERE Name='After logger failure';"), '1')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')

    def test_unavailable_audit_helper_cannot_replace_the_original_exception(self):
        self.sql(f'USE `{self.database}`; DROP PROCEDURE sp_TryRecordRejectedDiagnostic;')
        diagnostic = self.capture_customer_failure()
        self.assertEqual(diagnostic, {'state':'45000','number':53007,'message':'Requested record does not exist','clean':1})
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')

    def test_actor_failure_logs_exact_diagnostics_before_business_transaction_starts(self):
        diagnostic = self.capture_customer_failure(requested_actor=1)
        self.assertEqual(diagnostic, {'state':'45000','number':52002,'message':'Acting user must be the logged-in user','clean':1})
        self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,ErrorMessage,TransactionOutcome,UserID,SessionAccount,"
            "JSON_EXTRACT(NewValue,'$.RequestedUserID'),ContextID IS NOT NULL FROM AuditLog "
            "WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),
            '52002\t45000\tActing user must be the logged-in user\tnot_started\t2\tsa_amy@localhost\t1\t1')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')

    def draft_invoice_line(self):
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f'CALL sp_CompleteRepair({repair},1,NULL,NULL);')
        self.invoke('sp_SetServiceAppointmentStatus', appointment, 'Completed', None)
        invoice = int(self.invoke('sp_CreateInvoice', appointment, self.value('SELECT UTC_DATE();'), 10))
        line = int(self.invoke('sp_CreateInvoiceLineItem', invoice, 'Labor', 1, 10).split('\t')[-1])
        return invoice, line

    def test_invoice_line_rejections_preserve_parent_error_precedence_and_audit_ids(self):
        invoice, line = self.draft_invoice_line()
        self.invoke('sp_FinalizeInvoice', invoice)
        for name, args in [('sp_UpdateInvoiceLineItem', ('Denied',1,10)), ('sp_DeleteInvoiceLineItem', ())]:
            for target, number, message in [(line,54003,'Finalized line items cannot be modified'),
                                            (999999,53007,'Requested parent record does not exist')]:
                with self.subTest(procedure=name, target=target):
                    self.invoke(name, target, *args, error=f'ERROR {number}')
                    self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,ErrorMessage,TransactionOutcome,"
                        "AffectedRecordID IS NULL,JSON_TYPE(JSON_EXTRACT(NewValue,'$.RecordID'))='NULL' FROM AuditLog "
                        "WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),
                        f'{number}\t45000\t{message}\trolled_back\t1\t1')
        self.assertEqual(self.value(f'SELECT Description,Quantity,UnitPrice FROM InvoiceLineItem WHERE InvoiceLineItemID={line};'), 'Labor\t1\t10.00')

    def test_invoice_line_update_and_delete_still_lock_the_parent_and_roll_back(self):
        invoice, line = self.draft_invoice_line()
        class Log:
            def write(self, message): pass
        command = [self.mysql,'--no-defaults','--protocol=SOCKET',f'--socket={self.socket}',
            '--user=vsm_developer','--batch','--raw','--skip-column-names','--skip-force','--unbuffered']
        before = self.value(f'SELECT COUNT(*) FROM InvoiceLineItemHistory WHERE InvoiceLineItemID={line};')
        with Session(command,self.build_env(),Log()) as blocker:
            blocker.run(f'USE `{self.database}`; START TRANSACTION; SELECT InvoiceID FROM Invoice WHERE InvoiceID={invoice} FOR UPDATE;')
            for call in [f"sp_UpdateInvoiceLineItem({line},'Blocked',2,10,NULL)", f'sp_DeleteInvoiceLineItem({line},NULL)']:
                self.actor('sa_amy', f'SET innodb_lock_wait_timeout=1; CALL {call};', 'ERROR 1205')
                self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,TransactionOutcome,AffectedRecordID IS NULL FROM AuditLog "
                    "WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), '1205\tHY000\trolled_back\t1')
            blocker.run('ROLLBACK;')
        self.assertEqual(self.value(f'SELECT Description,Quantity FROM InvoiceLineItem WHERE InvoiceLineItemID={line};'), 'Labor\t1')
        self.assertEqual(self.value(f'SELECT COUNT(*) FROM InvoiceLineItemHistory WHERE InvoiceLineItemID={line};'), before)
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')

    def test_current_wrapper_deadlock_preserves_exact_wire_and_audit_diagnostics(self):
        customer = int(self.invoke('sp_CreateCustomer', 'Deadlock target', None, None))
        other = int(self.invoke('sp_CreateCustomer', 'Deadlock blocker', None, None))
        source = (self.fixture/'sql/04_procedures.sql').read_text()
        procedure = re.search(r'CREATE PROCEDURE sp_UpdateCustomer\([\s\S]*?\nEND //', source)[0]
        marker = '    UPDATE Customer SET '
        self.assertEqual(procedure.count(marker), 1)
        procedure = procedure.replace(marker, "    SELECT 'target_locked';\n"
            f'    SELECT CustomerID INTO @test_other_id FROM Customer WHERE CustomerID={other} FOR UPDATE;\n' + marker)
        self.sql(f'USE `{self.database}`;\nDELIMITER //\nDROP PROCEDURE sp_UpdateCustomer //\n' + procedure + '\nDELIMITER ;\n')
        self.admin_sql(f"GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_UpdateCustomer TO 'role_service_advisor';")
        blocker = errors.ErrorHandlingTests.process(self)
        caller = errors.ErrorHandlingTests.process(self, 'sa_amy', 'Advisor#2026')
        try:
            blocker.stdin.write('START TRANSACTION; INSERT INTO Customer (CustomerID,Name) '
                'WITH RECURSIVE n AS (SELECT 8000 AS id UNION ALL SELECT id+1 FROM n WHERE id<8099) '
                "SELECT id,CONCAT('Deadlock fixture ',id) FROM n; "
                f"SELECT CustomerID FROM Customer WHERE CustomerID={other} FOR UPDATE; SELECT 'locked';\n")
            blocker.stdin.flush()
            self.assertEqual(blocker.stdout.readline().strip(), str(other))
            self.assertEqual(blocker.stdout.readline().strip(), 'locked')
            caller.stdin.write(f"CALL sp_UpdateCustomer({customer},'Must roll back',NULL,NULL,NULL);\n")
            caller.stdin.close()
            caller.stdin = None
            self.assertEqual(caller.stdout.readline().strip(), 'target_locked')
            blocker.stdin.write(f'SELECT CustomerID FROM Customer WHERE CustomerID={customer} FOR UPDATE; COMMIT;\n')
            blocker.stdin.close()
            blocker.stdin = None
            out, error = caller.communicate(timeout=15)
            self.assertNotEqual(caller.returncode, 0, out)
            diagnostic = re.search(r'ERROR (\d+) \((\w+)\) at line \d+: (.*)', error)
            self.assertIsNotNone(diagnostic, error)
            self.assertEqual((diagnostic[1],diagnostic[2]), ('1213','40001'))
            out, error = blocker.communicate(timeout=15)
            self.assertEqual(blocker.returncode, 0, out+error)
            self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,ErrorMessage,ErrorClass,TransactionOutcome "
                "FROM AuditLog WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),
                f'1213\t40001\t{diagnostic[3]}\tretryable\trolled_back')
            self.assertEqual(self.value(f'SELECT Name FROM Customer WHERE CustomerID={customer};'), 'Deadlock target')
            self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'), '0')
        finally:
            errors.ErrorHandlingTests.finish(self, caller)
            errors.ErrorHandlingTests.finish(self, blocker)

    def test_successful_calls_commit_independently_and_do_not_chain_transactions(self):
        # Session completion_type=CHAIN cannot leave a procedure-owned transaction open.
        self.actor('sa_amy',"SET completion_type=1; CALL sp_CreateCustomer('Committed API',NULL,NULL,NULL); ROLLBACK;")
        self.assertEqual(self.value("SELECT COUNT(*) FROM Customer WHERE Name='Committed API';"),'1')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def test_current_noop_migration_preserves_business_revision_and_coverage(self):
        before=self.value('SELECT COUNT(*) FROM CustomerHistory;')
        result=self.build('--migrate')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertNotIn('OPERATION migration',result.stdout)
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory;'),before)
        self.assertEqual(self.value('SELECT revision,status FROM schema_revisions;'),'7\tinstalled')

    def test_concurrent_procedure_updates_serialize_temporal_versions(self):
        from concurrent.futures import ThreadPoolExecutor
        customer=int(self.invoke('sp_CreateCustomer','Concurrent customer',None,None))
        barrier=threading.Barrier(2)
        def update(name):
            barrier.wait(timeout=10)
            return self.invoke('sp_UpdateCustomer',customer,name,None,None)
        with ThreadPoolExecutor(max_workers=2) as workers:
            results=list(workers.map(update,['Concurrent A','Concurrent B']))
        self.assertEqual(len(results),2)
        self.assertEqual(self.value(f'SELECT GROUP_CONCAT(HistoryVersion ORDER BY HistoryVersion),SUM(HistoryIsCurrent) FROM CustomerHistory WHERE CustomerID={customer};'),'1,2,3\t1')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')

    def test_native_lock_timeout_rolls_back_new_wrapper_and_preserves_diagnostics(self):
        customer=int(self.invoke('sp_CreateCustomer','Locked customer',None,None))
        class Log:
            def write(self,message): pass
        command=[self.mysql,'--no-defaults','--protocol=SOCKET',f'--socket={self.socket}',
                 '--user=vsm_developer','--batch','--raw','--skip-column-names','--skip-force','--unbuffered']
        with Session(command,self.build_env(),Log()) as blocker:
            blocker.run(f'USE `{self.database}`; START TRANSACTION; SELECT CustomerID FROM Customer WHERE CustomerID={customer} FOR UPDATE;')
            self.actor('sa_amy',f"SET innodb_lock_wait_timeout=1; CALL sp_UpdateCustomer({customer},'Denied',NULL,NULL,NULL);",'ERROR 1205')
            blocker.run('ROLLBACK;')
        self.assertEqual(self.value(f'SELECT Name FROM Customer WHERE CustomerID={customer};'),'Locked customer')
        self.assertEqual(self.value("SELECT ErrorNumber,ErrorSQLSTATE,ErrorClass,TransactionOutcome FROM AuditLog WHERE Action='Rejected' ORDER BY AuditLogID DESC LIMIT 1;"),'1205\tHY000\tretryable\trolled_back')
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')


    def test_repair_creation_and_appointment_closing_cannot_both_win_a_race(self):
        from concurrent.futures import ThreadPoolExecutor
        appointment=self.book()
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'Checked In',None)
        self.invoke('sp_SetServiceAppointmentStatus',appointment,'In Progress',None)
        barrier=threading.Barrier(2)
        statements=[f"CALL sp_CreateRepair({appointment},UTC_TIMESTAMP(),'Diagnostic','Concurrent repair',1,NULL);",
                    f"CALL sp_SetServiceAppointmentStatus({appointment},'Completed',NULL,NULL);"]
        def execute(statement):
            barrier.wait(timeout=10)
            return self.account_sql('sa_amy','Advisor#2026',f'USE `{self.database}`; '+statement,check=False)
        with ThreadPoolExecutor(max_workers=2) as workers:
            results=list(workers.map(execute,statements))
        self.assertEqual(sum(result.returncode==0 for result in results),1,[r.stdout+r.stderr for r in results])
        self.assertTrue(any('ERROR 54005' in r.stderr for r in results),[r.stderr for r in results])
        self.assertEqual(self.value('SELECT COUNT(*) FROM OperationContext;'),'0')


class CurrentRevisionBuildTests(support.DisposableMySQLTestCase):
    def test_internal_audit_helper_definition_drift_is_rejected(self):
        path = self.fixture/'sql/04_procedures.sql'
        source = path.read_text()
        helper = re.search(r'CREATE PROCEDURE sp_TryRecordRejectedDiagnostic\([\s\S]*?\nEND //', source)[0]
        tampered = helper.replace('COMMIT AND NO CHAIN NO RELEASE;', 'ROLLBACK AND NO CHAIN NO RELEASE;')
        self.assertNotEqual(tampered, helper)
        path.write_text(source.replace(helper, tampered, 1))
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Consolidated revision 007 schema mismatch', result.stderr)
        self.assertIn('sp_tryrecordrejecteddiagnostic', result.stderr)
        self.assertEqual(self.scalar(f"SELECT status FROM `{self.database}`.schema_revisions;"), 'failed')
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status='covered';"), '0')

    def test_default_build_never_reads_historical_sql_and_inspects_principals_as_admin(self):
        import shutil
        shutil.rmtree(self.fixture/'sql/legacy')
        shutil.rmtree(self.fixture/'sql/migrations')
        (self.fixture/'sql/09_schema_migrations.sql').unlink()
        result=self.build()
        self.assert_success(result)
        self.assertIn('PASS\t45',result.stdout)
        self.assertIn('CONSOLIDATED REVISION 007: VERIFIED',result.stdout)
        self.assertNotIn('OPERATION migration',result.stdout)
        self.assertIn('ADMIN inspection: revision-007 native-principal collision preflight',result.stdout)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status='covered' AND baseline_version=6 AND applied_at IS NULL;"),'6')

    def test_parent_and_current_contract_tampering_fail_before_creation(self):
        for name in ['006_baseline.json','007_procedure_only.json']:
            path=self.fixture/'sql/consolidated'/name;original=path.read_bytes()
            path.write_bytes(original+b'\n')
            result=self.build()
            self.assertNotEqual(result.returncode,0)
            self.assertIn('contract checksum mismatch',result.stderr)
            self.assertFalse(self.database_exists())
            path.write_bytes(original)

    def test_unapproved_old_object_and_changed_new_api_are_rejected(self):
        path=self.fixture/'sql/04_procedures.sql'
        source=path.read_text()
        tampered = source.replace('Name = p_Name, Phone = p_Phone', "Name = 'Tampered', Phone = p_Phone", 1)
        self.assertNotEqual(tampered, source)
        path.write_text(tampered)
        result=self.build()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Consolidated revision 007 schema mismatch',result.stderr)
        self.assertIn('sp_updatecustomer',result.stderr)
        self.assertEqual(self.scalar(f"SELECT status FROM `{self.database}`.schema_revisions;"),'failed')
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status='covered';"),'0')
        path.write_text(source)
        other=self.database+'_old';self.grant_database(other)
        self.addCleanup(lambda:self.sql(f'DROP DATABASE IF EXISTS `{other}`;'))
        path=self.fixture/'sql/02_indexes.sql'
        path.write_text(path.read_text()+'\nCREATE INDEX UnapprovedNameIndex ON Customer(Phone);\n')
        result=self.build(database=other)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('TABLE:customer',result.stderr)

    def test_security_policy_and_assertion_source_tampering_refuse_before_reset(self):
        self.sql(f'CREATE DATABASE `{self.database}`; CREATE TABLE `{self.database}`.Sentinel(ID INT); INSERT INTO `{self.database}`.Sentinel VALUES(42);')
        for name in ['06_sample_data.sql','07_tests.sql','08_demo_accounts.sql','01_schema.sql']:
            path=self.fixture/'sql'/name;original=path.read_bytes();path.write_bytes(original+b'\n-- tampered\n')
            result=self.build('--dev-reset')
            self.assertNotEqual(result.returncode,0)
            self.assertIn('input checksum mismatch',result.stderr)
            self.assertEqual(self.scalar(f'SELECT ID FROM `{self.database}`.Sentinel;'),'42')
            path.write_bytes(original)

    def test_current_revision_and_object_provenance_cannot_be_forged(self):
        self.assert_success(self.build())
        self.sql(f"UPDATE `{self.database}`.schema_revisions SET contract_checksum=REPEAT('0',64);")
        result=self.build('--migrate')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('revision history',result.stderr)
        from consolidated_baseline import REVISION_SHA256
        self.sql(f"UPDATE `{self.database}`.schema_revisions SET contract_checksum='{REVISION_SHA256}'; UPDATE `{self.database}`.schema_object_versions SET revision_version=NULL WHERE object_name='sp_createcustomer';")
        result=self.build('--migrate')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('object provenance',result.stderr)

    def test_existing_target_roles_require_explicit_conversion_before_reset(self):
        self.sql(f'CREATE DATABASE `{self.database}`; CREATE TABLE `{self.database}`.Customer(ID INT); INSERT INTO `{self.database}`.Customer VALUES(42);')
        self.admin_sql(f"CREATE ROLE 'role_service_advisor'; GRANT SELECT,INSERT ON `{self.database}`.Customer TO 'role_service_advisor';")
        self.addCleanup(lambda:self.admin_sql("DROP ROLE IF EXISTS 'role_service_advisor';"))
        result=self.build('--dev-reset')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('explicit privilege conversion',result.stderr)
        self.assertEqual(self.scalar(f'SELECT ID FROM `{self.database}`.Customer;'),'42')
        # The fourth seeded identity must not inherit a preexisting native write path, even with demos.
        self.admin_sql("DROP ROLE 'role_service_advisor'; CREATE USER 'tech_carla'@'localhost' IDENTIFIED BY 'Existing#2026';")
        self.addCleanup(lambda:self.admin_sql("DROP USER 'tech_carla'@'localhost';"))
        result=self.build('--dev-reset','--with-demo-accounts')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('existing users/roles would collide',result.stderr)
        self.assertEqual(self.scalar(f'SELECT ID FROM `{self.database}`.Customer;'),'42')

    def test_unrelated_same_named_roles_are_untouched_on_collision_refusal(self):
        other=self.database+'_other';self.grant_database(other)
        self.sql(f'CREATE DATABASE `{other}`; CREATE TABLE `{other}`.Customer(ID INT);')
        self.addCleanup(lambda:self.sql(f'DROP DATABASE IF EXISTS `{other}`;'))
        self.admin_sql(f"CREATE ROLE 'role_service_advisor'; GRANT SELECT ON `{other}`.Customer TO 'role_service_advisor';")
        self.addCleanup(lambda:self.admin_sql("DROP ROLE IF EXISTS 'role_service_advisor';"))
        result=self.build()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('explicit privilege conversion',result.stderr)
        self.assertFalse(self.database_exists())
        self.assertEqual(self.admin_scalar(f"SELECT COUNT(*) FROM mysql.procs_priv WHERE User='role_service_advisor' AND Db='{self.database}';"),'0')

    def test_current_tools_preserve_historical_upgrade_and_separate_revision_scope(self):
        self.assert_success(self.build('--target-version','1'))
        self.sql(f"INSERT INTO `{self.database}`.Customer(CustomerID,Name) VALUES(9990,'Preserve upgrade');")
        result=self.build('--migrate')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.scalar(f'SELECT Name FROM `{self.database}`.Customer WHERE CustomerID=9990;'),'Preserve upgrade')
        self.assertEqual(self.scalar(f'SELECT MAX(version) FROM `{self.database}`.schema_migrations;'),'6')
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
            f"WHERE TABLE_SCHEMA='{self.database}' AND TABLE_NAME='schema_revisions';"),'0')

    def test_future_additive_migration_still_runs_once_on_current_revision(self):
        self.assert_success(self.build())
        self.add_migration('007_future_test.sql','CREATE TABLE FutureTest(ID INT PRIMARY KEY);\n')
        result=self.build('--migrate')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        before=self.migration_history()
        result=self.build('--migrate')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.migration_history(),before)
        self.assertEqual(self.scalar(f'SELECT status FROM `{self.database}`.schema_revisions;'),'installed')

    def test_all_historical_files_and_parent_contract_remain_exact(self):
        checkpoint='71696139e84a4e9b69f4baa6f89a6a8d20505561'
        for path in [*sorted((support.ROOT/'sql/migrations').glob('*')),support.ROOT/'sql/09_schema_migrations.sql']:
            relative=str(path.relative_to(support.ROOT))
            self.assertEqual(path.read_bytes(),subprocess.check_output(['git','-C',str(support.ROOT),'show',checkpoint+':'+relative]))
        for path in (support.ROOT/'sql/legacy/v001').glob('*.sql'):
            self.assertEqual(path.read_bytes(),subprocess.check_output(['git','-C',str(support.ROOT),'show',checkpoint+':sql/'+path.name]))
        self.assertEqual(hashlib.sha256((support.ROOT/'sql/consolidated/006_baseline.json').read_bytes()).hexdigest(),'94d124596a808d04cf00bcf0814ff6f2fd2c127426bef1c71205c9d21cf1dee2')

    def test_schema_level_dml_grants_cannot_survive_as_a_procedure_only_bypass(self):
        self.admin_sql("CREATE ROLE 'role_manager';")
        self.addCleanup(lambda:self.admin_sql("DROP ROLE 'role_manager';"))
        scope=support.accounts.database_scope(self.database)
        self.admin_sql(f"GRANT INSERT,UPDATE,DELETE ON `{scope}`.* TO 'role_manager';")
        result=self.build()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('explicit privilege conversion',result.stderr)
        self.assertFalse(self.database_exists())

    def test_invalid_admin_refuses_current_build_before_any_ddl(self):
        result=self.build('--admin-user','unavailable_admin')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.database_exists())
