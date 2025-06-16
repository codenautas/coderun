const pug = require('pug')
var stylus = require('stylus')
const fs = require('fs/promises')

async function deployPug(filename){
    const outfilename = `dist/${filename.replace(/\.(jade|pug)$/,'')}.html`
    const content = pug.renderFile(filename,{})
    await fs.writeFile(outfilename, content, 'utf8')
}

async function deployStylus(filename){
    const outfilename = `dist/${filename.replace(/\.(styl)$/,'')}.css`
    const rawContent = await fs.readFile(filename, 'utf8')
    const content = await new Promise((resolve, reject) => { 
        stylus.render(rawContent, {filename}, (err,content)=>{
            if (err) reject(err)
            else resolve(content);
        })
    })
    await fs.writeFile(outfilename, content, 'utf8')
}

async function copyFile(filename){
    await fs.copyFile(filename, `dist/${filename}`)
}

async function run(){
    try{
        await fs.mkdir('./dist', {recursive: true});
        console.log('deploying');
        console.log(await Promise.all([
            {fun: deployPug      , file:'index.jade'             },
            {fun: deployPug      , file:'aplicaciones-bp.jade'             },
            {fun: deployStylus   , file:'documentador-backend-plus.styl'   },
            {fun: copyFile       , file:'documentador-backend-plus.js'     }
        ].map(async ({fun, file}, i)=>{
            var result = []
            result.push(`${fun.name ?? ``}: ${file}`);
            try{
                await fun(file)
                result.push('ok')
            }catch(err){
                result.push(err)
            }
            return result
        })))
        console.log('deployed ok');
    }catch(err){
        if (err.code != 'XXXXX') throw err
    }
}

run()
