(in-package :cl-user)
(defpackage qlot.server
  (:use :cl)
  (:import-from :qlot.source
                :*dist-base-url*
                :package-source
                :source-prepared
                :url-path-for
                :project.txt
                :distinfo.txt
                :releases.txt
                :systems.txt
                :archive)
  (:import-from :qlot.parser
                :prepare-qlfile)
  (:import-from :qlot.tmp
                :*tmp-directory*)
  (:import-from :clack
                :clackup
                :stop)
  (:import-from :clack.response
                :headers)
  (:import-from :ningle
                :<app>
                :route
                :not-found
                :*response*)
  (:import-from :alexandria
                :when-let)
  (:export :localhost
           :start-server
           :stop-server))
(in-package :qlot.server)

(defvar *handler* nil)

(defvar *qlot-port* nil)

(defun localhost (&optional (path ""))
  ;; Use PATH If PATH is an URL, not an URL path.
  (when (and (< 0 (length path))
             (not (char= (aref path 0) #\/)))
    (return-from localhost path))

  (unless *qlot-port*
    (error "~S is not set." '*qlot-port*))
  (format nil "http://127.0.0.1:~D~A"
          *qlot-port*
          path))

(defun port-available-p (port)
  (handler-case (let ((socket (usocket:socket-listen "127.0.0.1" port :reuse-address t)))
                  (usocket:socket-close socket))
    (usocket:address-in-use-error (e) (declare (ignore e)) nil)))

(defun random-port ()
  "Return a port number not in use from 50000 to 60000."
  (loop for port from (+ 50000 (random 1000)) upto 60000
        if (port-available-p port)
          return port))

(defun make-app (sources)
  (flet ((make-route (source action)
           (lambda (params)
             (declare (ignore params))
             (let ((action-name (symbol-name action)))
               (when (string-equal (subseq action-name (- (length action-name) 4))
                                   ".txt")
                 (setf (headers *response* :content-type) "text/plain")))
             (let ((*dist-base-url* (localhost)))
               (funcall (symbol-function action) source)))))
    (let ((app (make-instance '<app>))
          (tmp-directory *tmp-directory*))
      (dolist (source sources)
        (setf (route app (url-path-for source 'project.txt))
              (lambda (params)
                (let ((*tmp-directory* tmp-directory))
                  (package-source source))
                (dolist (action '(project.txt distinfo.txt releases.txt systems.txt archive))
                  (when-let ((path (url-path-for source action)))
                    (setf (route app path)
                          (make-route source action))))

                (funcall (make-route source 'project.txt) params))))
      app)))

(defgeneric start-server (sources)
  (:method ((sources list))
    (when *handler*
      (stop-server))

    (let ((port (random-port)))
      (prog1
          (setf *handler*
                (let ((*standard-output* (make-broadcast-stream))
                      (app (make-app sources)))
                  (clackup app :port port)))
        (setf *qlot-port* port))))
  (:method ((qlfile pathname))
    (start-server (prepare-qlfile qlfile))))

(defun stop-server ()
  (when *handler*
    (stop *handler*)
    (setf *handler* nil
          *qlot-port* nil)))
