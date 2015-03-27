(defpackage :mpi-benchmarks
  (:documentation "benchmark suite for MPI under Lisp")
  (:nicknames #:cl-mpi-benchmarks)
  (:use #:cl #:mpi #:uiop #:cffi)
  (:import-from #:cl-mpi
                mpi-comm-rank mpi-comm-size mpi-comm-create
                mpi-comm-group mpi-group-select-from
                mpi-send mpi-receive mpi-wtime)
  (:import-from #:static-vectors
                make-static-vector free-static-vector static-vector-pointer)
  (:export run-benchmarks))

(in-package :mpi-benchmarks)

(defun run-benchmarks (&key (max-msg-size 1000000) (iterations 100000))
  (mpi-init)
  (let ((max-processes (mpi-comm-size MPI_COMM_WORLD))
        (all-ranks (mpi-comm-group MPI_COMM_WORLD)))
    (if (= 1 max-processes)
        (error "At least two MPI processes are required for the benchmarks"))
    (format t "running benchmarks ...~%")
    (loop for processes = 2 then (* processes 2) until (> processes max-processes) do
         (loop for msg-size  = 1 then (* msg-size 2)  until (> msg-size max-msg-size)
            with comm = (mpi-comm-create (mpi-group-select-from all-ranks (list 0 (1- processes)))) do
              (let ((sendbuf (make-static-vector msg-size :initial-element 0))
                    (recvbuf (make-static-vector msg-size :initial-element 0)))
                (fast-pingpong sendbuf recvbuf iterations comm)
                (free-static-vector sendbuf)
                (free-static-vector recvbuf))))))

(defun fast-pingpong (sendbuf recvbuf iterations comm)
  (let ((rank (mpi-comm-rank comm))
        (msg-size (length sendbuf))
        (sbuf (static-vector-pointer sendbuf))
        (rbuf (static-vector-pointer recvbuf)))
    (declare (type (signed-byte 32) rank msg-size iterations))
    (loop repeat 10 do (mpi-barrier comm))
    (let ((t-begin (mpi-wtime)))
      (locally (declare (optimize speed))
        (loop repeat iterations do
             (if
              (evenp rank)
              (let ((target-rank (+ 1 rank)))
                (mpi-send-foreign target-rank sbuf msg-size :byte :comm comm)
                (mpi-receive-foreign target-rank rbuf msg-size :byte :comm comm))
              (let ((target-rank (- 1 rank)))
                (declare (fixnum target-rank))
                (mpi-receive-foreign target-rank rbuf msg-size :byte :comm comm)
                (mpi-send-foreign target-rank sbuf msg-size :byte :comm comm)))))
      (let* ((seconds (- (mpi-wtime) t-begin))
             (usec (* seconds 1000000.0))
             (usec/iter (/ usec iterations)))
        (if (= 0 rank)
            (format t "pingpong(~A bytes) ~A usec/iteration~%" msg-size usec/iter))))))