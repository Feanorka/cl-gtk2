(in-package :gobject)

(defcallback lisp-closure-finalize :void ((data :pointer)
                                          (closure (:pointer lisp-closure)))
  (declare (ignore data))
  (finalize-lisp-closure closure))

(defun call-with-restarts (fn args)
  (restart-case
      (apply fn args)
    (return-from-g-closure (&optional v) :report "Return value from closure" v)))

(defcallback lisp-closure-marshal :void ((closure (:pointer lisp-closure))
                                         (return-value (:pointer g-value))
                                         (count-of-args :uint)
                                         (args (:pointer g-value))
                                         (invocation-hint :pointer)
                                         (marshal-data :pointer))
  (declare (ignore invocation-hint marshal-data))
  (let* ((args (parse-closure-arguments count-of-args args))
         (function-id (foreign-slot-value closure 'lisp-closure :function-id))
         (return-type (and (not (null-pointer-p return-value))
                           (gvalue-type return-value)))
         (fn (get-stable-pointer-value function-id))
         (fn-result (call-with-restarts fn args)))
    (when return-type
      (set-g-value return-value fn-result return-type :g-value-init nil))))

(defun parse-closure-arguments (count-of-args args)
  (loop
     for i from 0 below count-of-args
     collect (parse-gvalue (mem-aref args 'g-value i))))

(defun create-closure (fn)
  (let ((function-id (allocate-stable-pointer fn))
        (closure (g-closure-new-simple (foreign-type-size 'lisp-closure) (null-pointer))))
    (setf (foreign-slot-value closure 'lisp-closure :function-id) function-id)
    (g-closure-add-finalize-notifier closure (null-pointer)
                                     (callback lisp-closure-finalize))
    (g-closure-set-marshal closure (callback lisp-closure-marshal))
    closure))

(defun g-signal-connect (object signal handler &key after)
  "Deprecated alias for @fun{connect-signal}"
  (connect-signal object signal handler :after after))

(defun connect-signal (object signal handler &key after)
  "Connects the function to a signal for a particular object.
If @code{after} is true, then the function will be called after the default handler of the signal.

@arg[object]{an instance of @class{gobject}}
@arg[signal]{a string; names the signal}
@arg[handler]{a function; handles the signal. Number (and type) of arguments and return value type depends on the signal}
@arg[after]{a boolean}"
  (g-signal-connect-closure (ensure-object-pointer object)
                            signal
                            (create-closure handler)
                            after))

(defun finalize-lisp-closure (closure)
  (let ((function-id (foreign-slot-value closure 'lisp-closure :function-id)))
    (free-stable-pointer function-id)))