import json, csv

## Calculates objective function result value 
## Input: searchspacejson , outputcsvfile from benchmark , objective function variables as string.
## Output: objective function result value.
## If no objective variables are defined, it will check if they are defined in searchspace.
## Gets the objective function from searchspace and replace it with the values
## from outputcsv file to evaluate objective function result.

def calcobj(searchspacejson, outputcsvfile, objfuncvariables):
    ## Convert the string of objective function variables defined into list
    if objfuncvariables != "":
        objfunc_variables = list(objfuncvariables.split(","))

    funcvariables = []
    with open(searchspacejson) as f:
        sdata1 = json.load(f)

        for sdata in sdata1:
            ## Get objective function
            if sdata == "objective_function":
                objf = sdata1["objective_function"]
            ## Get function variables from searchspace if defined and if objfuncvariables is empty.
            if sdata == "function_variables":
                if objfuncvariables == "":
                    funcvar = sdata1["function_variables"]
                    for fvar in funcvar:
                        for fkeys in fvar.keys():
                            if(fkeys == "name"):
                                funcvariables.append(fvar.get(fkeys))

    if objfuncvariables == "":
        objfunc_variables = funcvariables

    with open(outputcsvfile, 'r', newline='') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        csvheader = reader.fieldnames
        for row in reader:
            for x in objfunc_variables:
                for k,v in row.items():
                    if (k == x):
                        objf = objf.replace(x , v)
    try:
        print(eval(objf))
    except:
        print("-1")


