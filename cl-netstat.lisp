;;;; cl-stats.lisp

(in-package #:cl-netstat)

;;; "cl-stats" goes here. Hacks and glory await!


;; .oO -> ...OOO.o (10mb/s)
;;        ..OOO.oO (20mb/s)
;;        .OOO.oOO (20mb/s)
;;        OOO.oOOo (10mb/s)
;;        OO.oOOo. ( 5mb/s)

(defclass array-loop ()
  ((size :initarg :size)
   (data)
   (index :initform 0)))

(defmethod initialize-instance :after ((array-loop array-loop) &rest initargs)
  (declare (ignorable initargs))
  (with-slots (size data) array-loop
    (setf data (make-array size :initial-element 0))))

(defmethod push-element ((array-loop array-loop) element)
  (with-slots (size data index) array-loop
    (setf (aref data (setf index (mod (1+ index) size)))
          element)))

(defmethod get-list ((array-loop array-loop))
  (with-slots (size data index) array-loop
    (loop :for i :from index :downto (1+ (- index size))
          :collect (aref data
                         (if (>= i 0)
                             i
                             (+ i size))))))

(defmethod get-max ((array-loop array-loop))
  (reduce #'max (slot-value array-loop 'data)))

(defmethod to-string-thing ((array-loop array-loop))
  (let* ((max (get-max array-loop))
         (lower-bound (/ max 3))
         (upper-bound (* 2 lower-bound)))
    (concatenate 'string
                 (loop :for i :in (get-list array-loop)
                       :collect (cond
                                  ((< i lower-bound) #\.)
                                  ((< i upper-bound) #\o)
                                  (t #\O))))))

(defmethod format-graph ((array-loop array-loop) window)
  (let* ((lst (get-list array-loop))
         (max (reduce #'max lst))
         (lower-bound (/ max 3))
         (upper-bound (* 2 lower-bound)))
    (loop :for nbr :in lst
          :do (with-style (window (list (if (eql 0 nbr)
                                            :white
                                            (list :number (color-size->term nbr)))
                                        :black))
                (croatoan:add-char window
                                   (cond
                                     ((= nbr 0) #\_)
                                     ((< nbr lower-bound) #\.)
                                     ((< nbr upper-bound) #\o)
                                     (t #\O)))))))

(let ((xb (ash 1 53)) ;; 8xb
      (tb (ash 1 43)) ;; 8tb
      (gb (ash 1 33)) ;; 8gb
      (mb (ash 1 23)) ;; 8mb
      (kb (ash 1 13)));; 8kb
  (defun format-size (size &optional (when-zero nil when-zero-given?))
    "formats given size (number) to a more readable format (string),
    when-zero can be given to return it instead of \"0Byt\""
    (if (and (eql 0 size)
             when-zero-given?)
        when-zero
        (values
         (cond
           ((> size xb) (format nil "~4d PiB" (ash size -50)))
           ((> size tb) (format nil "~4d TiB" (ash size -40)))
           ((> size gb) (format nil "~4d GiB" (ash size -30)))
           ((> size mb) (format nil "~4d MiB" (ash size -20)))
           ((> size kb) (format nil "~4d KiB" (ash size -10)))
           (t           (format nil "~4d Byt" size)          ))
         (list :black
               (if (eql 0 size)
                   :white
                   (list :number (get-match (get-size-color size)))))))))

(defun get-interface-data ()
  (with-open-file (stream "/proc/net/dev"
                          :direction :input)
    ;; ignore first 2 lines
    (dotimes (ignored 2) (read-line stream nil nil))
    (loop :for line = (read-line stream nil nil)
          :while line
          :collect (destructuring-bind (interface data)
                       (cl-ppcre:split ":" (string-trim " " line))
                     (cons interface (mapcar (lambda (val data)
                                               (cons val
                                                     (parse-integer data)))
                                             (list :rec-bytes :rec-packets :rec-errs
                                                   :rec-drop :rec-fifo :rec-frame
                                                   :rec-compressed :rec-multicast
                                                   :trans-bytes :trans-packets :trans-errs
                                                   :trans-drop :trans-fifo :trans-colls
                                                   :trans-carrier :trans-compressed)
                                             (cdr (cl-ppcre:split "\\s+" data))))))))


(defmacro assoc-chain (args data)
  `(assoc ,(car (last args))
          ,(if (cdr args)
               `(cdr (assoc-chain ,(butlast args)
                                  ,data))
               data)
          :test #'equalp))

(defmacro with-assocs (bindings data &body body)
  (let ((data-sym (gensym "data")))
    `(let ((,data-sym ,data))
       (let ,(loop :for (var chain) :in bindings
                   :collect (list var `(assoc-chain ,chain ,data-sym)))
         ,@body))))

(defmacro mapassoc (function list &rest more-lists)
  (let ((args (gensym "args")))
    `(mapcar (lambda (&rest ,args)
               (cons (caar ,args)
                     (apply ,function
                            (mapcar #'cdr ,args))))
             ,list
             ,@more-lists)))

(defmacro with-style ((window color-pair &optional attributes) &body body)
  (let ((old-color-pair (gensym "old-color-pair"))
        (old-attributes (gensym "old-attributes"))
        (new-color-pair (gensym "new-color-pair"))
        (new-attributes (gensym "new-attributes")))
    `(let ((,old-color-pair (croatoan:.color-pair ,window))
           (,old-attributes (croatoan:.attributes ,window))
           (,new-color-pair ,color-pair)
           (,new-attributes ,attributes))
       (when ,new-color-pair
         (setf (croatoan:.color-pair ,window) ,new-color-pair))
       (when ,new-attributes
         (setf (croatoan:.attributes ,window) ,new-attributes))
       (prog1 (progn ,@body)
         (when ,new-color-pair
           (setf (croatoan:.color-pair ,window)
                 ,old-color-pair))
         (when ,new-attributes
            (setf (croatoan:.attributes ,window)
                  ,old-attributes))))))

(defun format-interface-data (data)
  (loop :for (interface . data) :in data
        :collect (cons interface
                       (mapassoc #'format-size
                                 data))))

(defun diff-interface-data (a b)
  (loop :for (interface-a . data-a) :in a
        :for (interface-b . data-b) :in b
        :when (string= interface-a interface-b)
        :collect (cons interface-a
                       (mapassoc #'- data-b data-a))))

(defparameter *last-stats* nil)
(setf *last-stats* (get-interface-data))

(defparameter *interface-graphs* nil)
(setf *interface-graphs* (make-hash-table :test 'equal))

(defun update-graphs (stats)
  (loop :for (interface . stat) :in stats
        :unless (gethash interface *interface-graphs*)
        :do (setf (gethash interface *interface-graphs*)
                  (make-instance 'array-loop :size 8)))
  (loop :for key :being :the :hash-key :of *interface-graphs*
        :do (let ((data (cdr (assoc key stats :test #'equal))))
              (push-element (gethash key *interface-graphs*)
                            (if data
                                (+ (nth 2 data)
                                   (nth 3 data))
                                0)))))

(defun format-interfaces (window stats)
  (with-style (window '(:white :black) '(:bold :underline))
    (croatoan:add-string window
                         (format nil "~12,,,' a~{ ~8,,,' a~}"
                                 "NETWORK"
                                 (list "Total Rx" "Total Tx" "Rx/s" "Tx/s" "Graph"))))
  (loop :for stat :in stats
        :do
        (croatoan:new-line window)
        (croatoan:add-string window
                             (format nil "~12,,,' a" (car stat)))
        (loop :for bytes :in (cdr stat)
              :do (multiple-value-bind (str color)
                      (format-size bytes)
                    (croatoan:add-char window #\Space)
                    (with-style (window color)
                      (croatoan:add-string window
                                           (format nil "~8,,,' a" str)))))
        (croatoan:add-char window #\Space)
        (format-graph (gethash (car stat) *interface-graphs*) window)))

(defun gen-stats (last cur)
  (loop :for (interface . data) :in (diff-interface-data last cur)
        :collect (list interface
                       (cdr (assoc-chain (interface :rec-bytes) cur))
                       (cdr (assoc-chain (interface :trans-bytes) cur))
                       (cdr (assoc-chain (:rec-bytes) data))
                       (cdr (assoc-chain (:trans-bytes) data)))))

(defparameter *win* nil)

(defun draw (scr)
  (sleep 1.0)
  (croatoan:clear scr)
  (croatoan:move scr 0 0)
  (setf (croatoan:.color-pair scr)
        '(:white :black))
  (let ((stats (gen-stats *last-stats* (setf *last-stats* (get-interface-data)))))
    ;;(croatoan:new-line scr)
    ;; (let ((window (make-instance'croatoan:window))))
    (update-graphs stats)
    (format-interfaces scr stats)
    ;; (loop :for i :from 16 :to 255
    ;;       :do
    ;;       (when (eql 0 (mod (- i 4) 6))
    ;;         (croatoan:new-line scr))
    ;;       (with-style (scr (list :black (list :number i)))
    ;;         (croatoan:add-string scr (format nil "~4,,,' a " i))))
    (croatoan:refresh scr)))

(defun window ()
  (croatoan:with-screen (scr :input-echoing nil
                             :input-blocking nil
                             :enable-fkeys t
                             :cursor-visibility nil)
    (croatoan:clear scr)
    (croatoan:box scr)
    (croatoan:refresh scr)
    (croatoan:event-case (scr event)
      (#\q (return-from croatoan:event-case))
      ((nil)
       (draw scr)))))

(defun red-yellow-green-gradient-generator (count)
  (let ((red 255)
        (green 0)
        (step-size (/ 255 (/ count 2))))
    (flet ((fmt (red green)
             (format nil "#~2,'0X~2,'0X00" (round red) (round green))))
      (reverse
       (append
        (loop :while (< green 255)
              :do (incf green step-size)
              :when (> green 255)
              :do (setf green 255)
              :collect (fmt red green))
        (loop :while (> red 0)
              :do (decf red step-size)
              :when (< red 0)
              :do (setf red 0)
              :collect (fmt red green)))))))

(defun color-size->term (size)
  (get-match (get-size-color size)))

(let ((lookup (make-array '(42)
                          :initial-contents (red-yellow-green-gradient-generator 42)
                          :adjustable nil)))
  (defun get-size-color (size)
    (let ((spot (integer-length size)))
      (if (> spot 41)
          (aref lookup 41)
          (aref lookup spot)))))

(defun color-hashtag-p (color)
  (if (char-equal #\# (aref color 0)) t nil))

(defun color-rgb->string (r g b &optional hashtag-p)
  (concatenate 'string
               (when hashtag-p "#")
               (write-to-string r :base 16)
               (write-to-string g :base 16)
               (write-to-string b :base 16)))

(defun color-string->rgb (color)
  (when (color-hashtag-p color)
    (setf color (subseq color 1 7)))
  (values (parse-integer (subseq color 0 2) :radix 16)
          (parse-integer (subseq color 2 4) :radix 16)
          (parse-integer (subseq color 4 6) :radix 16)))

(let ((table (make-hash-table)))
  (defun get-match (color)
    (let ((match (gethash color table)))
      (when match
        (return-from get-match match)))
    (let ((best-match-diff (* 3 255))
          (best-match 0))
      (multiple-value-bind (r g b)
          (color-string->rgb color)
        (loop :for (k . (rr gg bb)) :in (mapassoc (lambda (rgb)
                                                    (mapcar (lambda (val)
                                                              (parse-integer val :radix 16))
                                                            rgb))
                                                  *term->rgb*)
              :do (let ((diff (reduce #'+
                                      (mapcar (alexandria:compose #'abs #'-)
                                              (list r g b)
                                              (list rr gg bb)))))
                    (when (< diff best-match-diff)
                      (setf best-match k
                            best-match-diff diff))
                    (when (eql 0 best-match-diff)
                      (return)))))
      (setf (gethash color table) best-match))))
