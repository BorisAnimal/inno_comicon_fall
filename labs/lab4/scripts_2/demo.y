%{
    #include <iostream>
    #include <list>
    extern int yylineno;
    extern int yylex();
    void yyerror(char *s) {
        std::cerr << s << ", line " << yylineno << std::endl;
        exit(1);
    }

    #define TOKENPASTE(x, y) x ## y
    #define TOKENPASTE2(x, y) TOKENPASTE(x, y)
    #define foreach(i, list) typedef typeof(list) TOKENPASTE2(T,__LINE__); \
                        for(TOKENPASTE2(T,__LINE__)::iterator i = list.begin(); i != list.end(); i++)

    class oper_t { // abstract
        protected: oper_t() {}
        public: virtual ~oper_t() {}
        virtual void print(int indent=0) =0;
    };

    class expr_t { // abstract
        protected: expr_t() {}
        public: virtual ~expr_t() {}
        virtual void print() =0;
    };

    class block : public oper_t {
        std::list<oper_t*> ops;
        void append(oper_t* op) {
            block* b = dynamic_cast<block*>(op);
            if(b) {
                ops.splice(ops.end(), b->ops, b->ops.begin(), b->ops.end());
                delete b;
            }
            else ops.push_back(op);
        }
        public:
            block() {}
            block(oper_t* op) { append(op); }
            block(oper_t* op1, oper_t* op2) { append(op1); append(op2); }
        int size() { return ops.size(); }
        virtual void print(int indent=0) {
            foreach(i, ops) {
                std::cout << std::string(indent, '\t');
                (*i)->print(indent);
            }
        }
        virtual ~block() { foreach(i, ops) delete *i; }
    };

    class exprop : public oper_t {
        expr_t* expr;
        public: exprop(expr_t* expr) : expr(expr) {}
        virtual void print(int indent=0) {
            expr->print();
            std::cout << ";" << std::endl;
        }
        virtual ~exprop() { delete expr; }
    };

    class ifop : public oper_t {
        expr_t* cond;
        block thenops, elseops;
        public: ifop(expr_t* cond, oper_t* thenops, oper_t* elseops) :
                cond(cond), thenops(thenops), elseops(elseops) {}
        virtual void print(int indent=0) {
            std::cout << "if "; cond->print();  std::cout << " {" << std::endl;
            thenops.print(indent+1);
            if (elseops.size()) {
                std::cout << std::string(indent, '\t') << "} else {" << std::endl;
                elseops.print(indent+1);
            }
            std::cout << std::string(indent, '\t') << "}" << std::endl;
        }
        virtual ~ifop() { delete cond; }
    };

    class whileop : public oper_t {
        expr_t* cond;
        block ops;
        public: whileop(expr_t* cond, oper_t* ops) : cond(cond), ops(ops) {}
        virtual void print(int indent=0) {
            std::cout << "while "; cond->print();  std::cout << " {" << std::endl;
            ops.print(indent+1);
            std::cout << std::string(indent, '\t') << "}" << std::endl;
        }
        virtual ~whileop() { delete cond; }
    };

    class exitop : public oper_t {
        virtual void print(int indent=0) { std::cout << "exit;" << std::endl; }
    };

    class binary : public expr_t {
        const char* op;
        expr_t *arg1, *arg2;
        public: binary(const char* op, expr_t *arg1, expr_t *arg2) :
                op(op), arg1(arg1), arg2(arg2) {}
        virtual void print() {
            std::cout<<"(";
            arg1->print();
            std::cout<<op;
            arg2->print();
            std::cout<<")";
        }
        virtual ~binary() { delete arg1; delete arg2; }
    };

    class assign : public expr_t {
        std::string name;
        expr_t* value;
        public: assign(const std::string& name, expr_t* value) :
                name(name), value(value) {}
        virtual void print() { std::cout<<name<<" = "; value->print(); }
        virtual ~assign() { delete value; }
    };

    class unary : public expr_t {
        const char* op;
        expr_t* arg;
        public: unary(const char* op, expr_t* arg) : op(op), arg(arg) {}
        virtual void print() { std::cout<<op; arg->print(); }
        virtual ~unary() { delete arg; }
    };

    class funcall : public expr_t {
        std::string name;
        std::list<expr_t*> args;
        public: funcall(const std::string& name,
                const std::list<expr_t*>& args) :
                name(name), args(args) {}
        virtual void print() {
            std::cout<<name<<"(";
            foreach(i,args) {
                if (i!=args.begin())
                    std::cout<<", ";
                (*i)->print();
            }
            std::cout<<")";
        }
        virtual ~funcall() { foreach(i,args) delete *i; }
    };

    class value : public expr_t {
        std::string text;
        public: value(const std::string& text) : text(text) {}
        virtual void print() { std::cout<<text; }
    };

    typedef struct {
        std::string str;
        oper_t* oper;
        expr_t* expr;
        std::list<expr_t*> args;
    } YYSTYPE;

    #define YYSTYPE YYSTYPE

    std::string replaceAll(const std::string& where, const std::string& what, const std::string& withWhat) {
        std::string result = where;
        while(1) {
            int pos = result.find(what);
            if (pos==-1) return result;
            result.replace(pos, what.size(), withWhat);
        }
    }
%}

%token IF ELSE WHILE EXIT
%token EQ LE GE NE
%token STRING NUM ID

%type<str> ID NUM STRING
%type<oper> OPS OP1 OP2 OP
%type<expr> EXPR EXPR1 EXPR2 TERM VAL ARG
%type<args> ARGS

%%

PROGRAM: OPS                            { $1->print(); delete $1; }
;

OPS:    OP                              // inherit
|       OPS OP                          { $$ = new block($1, $2); }
;

OP1:    '{' OPS '}'                     { $$ = $2; }
|       EXPR ';'                        { $$ = new exprop($1); }
|       IF '(' EXPR ')' OP1 ELSE OP1    { $$ = new ifop($3, $5, $7); }
|       WHILE '(' EXPR ')' OP1          { $$ = new whileop($3, $5); }
|       EXIT ';'                        { $$ = new exitop(); }
;

OP2:    IF '(' EXPR ')' OP              { $$ = new ifop($3, $5, new block()); }
|       IF '(' EXPR ')' OP1 ELSE OP2    { $$ = new ifop($3, $5, $7); }
|       WHILE '(' EXPR ')' OP2          { $$ = new whileop($3, $5); }
;

OP:     OP1 | OP2 ;                     // inherit

EXPR:   EXPR1                           // inherit
|       ID '=' EXPR                     { $$ = new assign($1, $3); }

EXPR1:  EXPR2                           // inherit
|       EXPR1 EQ EXPR2                  { $$ = new binary("==", $1, $3); }
|       EXPR1 LE EXPR2                  { $$ = new binary("<=", $1, $3); }
|       EXPR1 GE EXPR2                  { $$ = new binary(">=", $1, $3); }
|       EXPR1 NE EXPR2                  { $$ = new binary("!=", $1, $3); }
|       EXPR1 '>' EXPR2                 { $$ = new binary(">", $1, $3); }
|       EXPR1 '<' EXPR2                 { $$ = new binary("<", $1, $3); }
;

EXPR2:  TERM                            // inherit
|       EXPR2 '+' TERM                  { $$ = new binary("+", $1, $3); }
|       EXPR2 '-' TERM                  { $$ = new binary("-", $1, $3); }
;

TERM:   VAL                             // inherit
|       TERM '*' VAL                    { $$ = new binary("*", $1, $3); }
|       TERM '/' VAL                    { $$ = new binary("/", $1, $3); }
;

VAL:    NUM                             { $$ = new value($1); }
|       '-' VAL                         { $$ = new unary("-", $2); }
|       '!' VAL                         { $$ = new unary("!", $2); }
|       '(' EXPR ')'                    { $$ = $2; }
|       ID                              { $$ = new value($1); }
|       ID '(' ARGS ')'                 { $$=new funcall($1, $3); }
;

ARGS:                                   { $$.clear(); }
|       ARG                             { $$.clear(); $$.push_back($1); }
|       ARGS ',' ARG                    { $$ = $1; $$.push_back($3); }
;

ARG:    EXPR                            // inherit
|       STRING                          { $$=new value('"'+replaceAll($1, "\n", "\\n")+'"'); }
;

%%
int main() { return yyparse(); }