(in-package :jira-api)

(defun ensure-parent (object parent &key (err-if-nil t))
  (when (and (not err-if-nil) (null object))
    (return-from ensure-parent object))

  (unless (sheeple:parentp parent object)
    (push parent (sheeple:object-parents object))
    (sheeple:shared-init object))
  object)

(sheeple:defproto =status= () (name))
(sheeple:defproto =person= () (displayname emailaddress))
(sheeple:defproto =issue= () (fields key id self))
(sheeple:defproto =fields= () (summary description reporter creator assignee status))
(sheeple:defmessage show (object &rest args))
(sheeple:defmessage fields-labels (fields))
(sheeple:defreply fields-labels ((fields =fields=))
  (sheeple:with-properties (labels) fields
    labels))

(sheeple:defreply sheeple:shared-init :after ((issue =issue=) &key)
  (with-accessors ((fields fields)) issue
    (when fields
      (ensure-parent fields =fields=)
      (ensure-parent (status fields) =status=)
      (ensure-parent (reporter fields) =person=)
      (ensure-parent (creator fields) =person=)
      (ensure-parent (assignee fields) =person= :err-if-nil nil))))

(sheeple:defreply show ((person =person=) &rest args)
  (declare (ignore args))
  (format nil "\"~a\" <~a>" (displayname person) (emailaddress person)))

(sheeple:defreply show ((status =status=) &rest args)
  (declare (ignore args))
  (format nil "~a" (name status)))

(sheeple:defreply show ((issue =issue=) &rest args)
  (declare (ignorable args))
  (with-output-to-string (*standard-output*)
    (if-let ((fields (fields issue)))
      (with-accessors ((status status) (summary summary) (reporter reporter)
                                       (creator creator) (assignee assignee)
                                       (labels fields-labels)) fields

        (format t "~a (~a) <~a>~%"
                (key issue)
                (show status)
                (self issue))

        (show-summary summary)

        (show-person reporter "Reporter")
        (show-person creator "Creator")
        (when assignee
          (show-person assignee "Assignee"))

        (when (< 0 (length labels))
          (show-labels labels))

        (when (description fields)
          (show-description (description fields))))
      (fresh-line))))

(sheeple:defproto =project= () (name key issuetypes))

(sheeple:defproto =issuetype= () (description name))

(sheeple:defreply sheeple:shared-init :after ((project =project=) &key)
                  (declare (optimize (debug 3)))
  (with-accessors ((issuetypes issuetypes)) project
    (when issuetypes
      (map nil
           (lambda (issuetype) (ensure-parent issuetype =issuetype=))
           issuetypes))))

(sheeple:defreply show ((issuetype =issuetype=) &rest arg)
  (declare (ignore args))
  (with-output-to-string (*standard-output*)
    (pprint-logical-block (*standard-output* (tokens (description issuetype)))
      (pprint-indent :block 15 *standard-output*)
      (pprint-exit-if-list-exhausted)
      (format *standard-output* "~4t~10@a: " (name issuetype))
      (loop
        (princ (pprint-pop))
        (pprint-exit-if-list-exhausted)
        (pprint-newline :fill *standard-output*)
        (princ #\space)))))

(sheeple:defreply show ((project =project=) &rest args)
  (declare (ignore args))
  (with-output-to-string (*standard-output*)
    (format t "~a: ~a~%~{~a~&~}" (key project) (name project)
            (map 'list #'show (issuetypes project)))))

(deftype vector-of-objects () '(vector (or hash-table sheeple:object) *))

(defun json2sheeple (json &optional parent)
  (labels
    ((handle-parsed (parsed-json)
       (typecase parsed-json
         (vector-of-objects (map 'vector #'handle-parsed parsed-json))
         (hash-table
           (let ((result (sheeple:object)))
             (loop for json-prop being the hash-keys of parsed-json using (hash-value json-value)
                   do (setf (sheeple:property-value result
                                                    (intern (string-upcase json-prop) :jira-api))
                            (typecase json-value
                              (hash-table (handle-parsed json-value))
                              (vector-of-objects (map 'vector #'handle-parsed json-value))
                              (t json-value)))
                   finally (return result))))
         (t parsed-json))))
    (let* ((yason:*parse-json-arrays-as-vectors* t)
           (result (handle-parsed (yason:parse json))))
      (when parent
        (ensure-parent result parent))
      result)))

