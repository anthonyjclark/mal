import rl from './node_readline.mjs'
const readline = rl.readline
import { _clone, _list_Q, _malfunc, _malfunc_Q, Vector } from './types.mjs'
import { BlankException, read_str } from './reader.mjs'
import { pr_str } from './printer.mjs'
import { new_env, env_set, env_get } from './env.mjs'
import { core_ns } from './core.mjs'

// read
const READ = str => read_str(str)

// eval
const qq_loop = (acc, elt) => {
    if (_list_Q(elt) && elt.length == 2
        && elt[0] === Symbol.for('splice-unquote')) {
        return [Symbol.for('concat'), elt[1], acc]
    } else {
        return [Symbol.for('cons'), quasiquote (elt), acc]
    }
}
const quasiquote = ast => {
    if (_list_Q(ast)) {
        if (ast.length == 2 && ast[0] === Symbol.for('unquote')) {
            return ast[1]
        } else {
            return ast.reduceRight(qq_loop, [])
        }
    } else if (ast instanceof Vector) {
        return [Symbol.for('vec'), ast.reduceRight(qq_loop, [])]
    } else if (typeof ast === 'symbol' || ast instanceof Map) {
        return [Symbol.for('quote'), ast]
    } else {
        return ast
    }
}

const dbgevalsym = Symbol.for("DEBUG-EVAL")

const EVAL = (ast, env) => {
  while (true) {
    if (dbgevalsym in env) {
        const dbgeval = env_get(env, dbgevalsym)
        if (dbgeval !== null && dbgeval !== false) {
            console.log('EVAL:', pr_str(ast, true))
        }
    }

    if (typeof ast === 'symbol') {
        return env_get(env, ast)
    } else if (ast instanceof Vector) {
        return ast.map(x => EVAL(x, env))
    } else if (ast instanceof Map) {
        let new_hm = new Map()
        ast.forEach((v, k) => new_hm.set(k, EVAL(v, env)))
        return new_hm
    } else if (!_list_Q(ast)) {
        return ast
    }

    if (ast.length === 0) { return ast }

    const [a0, a1, a2, a3] = ast
    switch (typeof a0 === 'symbol' ? Symbol.keyFor(a0) : Symbol(':default')) {
        case 'def!':
            return env_set(env, a1, EVAL(a2, env))
        case 'let*':
            let let_env = new_env(env)
            for (let i=0; i < a1.length; i+=2) {
                env_set(let_env, a1[i], EVAL(a1[i+1], let_env))
            }
            env = let_env
            ast = a2
            break // continue TCO loop
        case 'quote':
            return a1
        case 'quasiquote':
            ast = quasiquote(a1)
            break // continue TCO loop
        case 'defmacro!':
            let func = _clone(EVAL(a2, env))
            func.ismacro = true
            return env_set(env, a1, func)
        case 'do':
            ast.slice(1, -1).map(x => EVAL(x, env))
            ast = ast[ast.length-1]
            break // continue TCO loop
        case 'if':
            let cond = EVAL(a1, env)
            if (cond === null || cond === false) {
                ast = (typeof a3 !== 'undefined') ? a3 : null
            } else {
                ast = a2
            }
            break // continue TCO loop
        case 'fn*':
            return _malfunc((...args) => EVAL(a2, new_env(env, a1, args)),
                            a2, env, a1)
        default:
            const f = EVAL(a0, env)
            if (f.ismacro) {
                ast = f(...ast.slice(1))
                break // continue TCO loop
            }
            const args = ast.slice(1).map(x => EVAL(x, env))
            if (_malfunc_Q(f)) {
                env = new_env(f.env, f.params, args)
                ast = f.ast
                break // continue TCO loop
            } else {
                return f(...args)
            }
    }
  }
}

// print
const PRINT = exp => pr_str(exp, true)

// repl
let repl_env = new_env()
const REP = str => PRINT(EVAL(READ(str), repl_env))

// core.EXT: defined using ES6
for (let [k, v] of core_ns) { env_set(repl_env, Symbol.for(k), v) }
env_set(repl_env, Symbol.for('eval'), a => EVAL(a, repl_env))
env_set(repl_env, Symbol.for('*ARGV*'), [])

// core.mal: defined using language itself
REP('(def! not (fn* (a) (if a false true)))')
REP('(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) "\nnil)")))))')
REP('(defmacro! cond (fn* (& xs) (if (> (count xs) 0) (list \'if (first xs) (if (> (count xs) 1) (nth xs 1) (throw "odd number of forms to cond")) (cons \'cond (rest (rest xs)))))))')

if (process.argv.length > 2) {
    env_set(repl_env, Symbol.for('*ARGV*'), process.argv.slice(3))
    REP(`(load-file "${process.argv[2]}")`)
    process.exit(0)
}


while (true) {
    let line = readline('user> ')
    if (line == null) break
    try {
        if (line) { console.log(REP(line)) }
    } catch (exc) {
        if (exc instanceof BlankException) { continue }
        if (exc instanceof Error) { console.warn(exc.stack) }
        else { console.warn(`Error: ${exc}`) }
    }
}
